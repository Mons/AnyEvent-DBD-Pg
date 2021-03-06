=for rem

$pool->txn(default => 'rollback', sub {
	my $db = shift;
	$db->do(... sub {
		
		$db->rollback;
	})
})

=cut

package AnyEvent::DBD::Pool::Tx;

use common::sense;

sub new {
	my $pkg = shift;
	my $dbh = shift;
	my $destroyer = shift;
	return bless {db => $dbh, des => $destroyer},$pkg;
}

sub commit {
	my $self = shift;
	$self->{commited} = 1;
	#warn "call commit on $self->{db}";
	$self->{db}->commit(@_ ? @_ : sub {});
}
sub rollback {
	my $self = shift;
	$self->{commited} = -1;
	#warn "call rollback on $self->{db}";
	$self->{db}->rollback(@_ ? @_ : sub {});
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = shift;
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;
	#warn "Call $method on db";
	$self->{db}->$method(@_);
	return;
	#unshift @_, $self->{db};
	#goto &{ $self->{db}->can($method) };

}

sub DESTROY {
	my $self = shift;
	#warn "DESTROY tx";
	local $@;eval {
		$self->{des}->($self);
	1} or warn "$self/DESTROY: $@";
	return;
}

package AnyEvent::DBD::Pool;

use common::sense;
use AnyEvent::DBD::Pg;

sub new {
	my $pkg = shift;
	my $count = shift;
	my $self = bless {}, $pkg;
	my ($dsn,$user,$pass,$args,@args) = @_;
	$args ||= {};
	
	my $ctor;
	if (@args and ref $args[0] eq 'CODE') {
		$ctor = shift @args;
	} else {
		#warn "dsn = $dsn";
		my ($type) = $dsn =~ /^dbi:([^:]+):/;
		my $class = "AnyEvent::DBD::".$type;
		eval "require $class; 1" or die $@;
		$ctor = sub {
			$class->new(@_);
		};
	}
	$self->{pool_size} = $count;
	$self->{pool} = [
		map { $ctor->( $dsn,$user,$pass,$args,@args,id => $_[0] ); } 1..$count
	];
	$self->{waiting_db} = [];
	return $self;
}

sub debug {
	my $self = shift;
	$_->debug(@_) for @{ $self->{pool} };
}

sub queue_size {
	my $self = shift;
	$_->queue_size(@_) for @{ $self->{pool} };
}

sub connect {
	my $self = shift;
	my $success = 1;
	$success &&= $_->connect(@_) for @{ $self->{pool} };
	$success;
}

sub freedb {
	my $self = shift;
	my $cb = pop;
	# During this call we must prohibit free pool changing. so
	$self->{take_delay} = \ my @take;
	$self->{ret_delay} = \ my @ret;
	for (@{ $self->{pool} }) {
		$cb->($_);
	}
	delete $self->{take_delay};
	delete $self->{ret_delay};
	$self->ret(@ret);
	$self->take($_) for @take;
}

sub DESTROY {}
our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = shift;
	my $cb = pop;
	my @args = @_;
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;
	warn "autoloaded $AUTOLOAD";
	$self->take(sub {
		my $con = shift;
		$con->$method(@args,sub {
			$self->ret($con);
			goto &$cb;
		});
	});
}

sub txn {
	my $self = shift;
	my $cb = pop;
	my %args = (default => 'commit', @_);
	my $ix = \0;
	$self->take(sub {
		my $db = shift;
		$db->begin_work(sub {
			my $wr = AnyEvent::DBD::Pool::Tx->new($db, sub {
				my $wr = shift;
				if ($wr->{commited}) {
					$self->ret($db);
				} else {
					my $call = $args{default};
					#warn "default commit";
					$db->$call(sub{
						shift or warn;
						$self->ret($db);
					});
				}
			});
			$cb->($wr);
		});
	});
	
}

sub take {
	my $self = shift;
	my $cb = shift or die "cb required for take at @{[(caller)[1,2]]}\n";
	#warn("take wrk, left ".$#{$self->{pool}}."\n");
	if ($self->{take_delay}) {
		push @{ $self->{take_delay} }, $cb;
		return;
	}
	if (@{$self->{pool}}) {
		my $db = shift @{$self->{pool}};
		$db->{_return_to_me} = $self;
		$cb->($db);
	} else {
		push @{$self->{waiting_db}},$cb;
		if ( @{$self->{waiting_db}} > $self->{pool_size} ) {
			warn("no worker for @{[(caller 1)[1,2]]}, maybe increase pool (current penfing: @{[ 0+@{$self->{waiting_db}} ]})?");
		}
	}
	return;
}

sub ret {
	my $self = shift;
	if ($self->{ret_delay}) {
		push @{ $self->{ret_delay} }, @_;
		return;
	}
	delete $_->{_return_to_me} for @_;
	push @{ $self->{pool} }, @_;
	#warn("ret wrk, left ".$#{$self->{pool}}."; waiting=".(0+@{ $self->{waiting_db} })."\n");
	$self->take(shift @{ $self->{waiting_db} }) if @{ $self->{waiting_db} };
	return;
}


1;

