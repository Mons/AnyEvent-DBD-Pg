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
	$self->{db}->commit(@_);
}
sub rollback {
	my $self = shift;
	$self->{commited} = -1;
	$self->{db}->rollback(@_);
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = shift;
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;
	$self->{db}->$method(@_);
	return;
	unshift @_, $self->{db};
	eval{ goto &{ $self->{db}->can($method) } } or die "$method: $@";
}

sub DESTROY {
	my $self = shift;
	$self->{des}->($self);
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
	warn "cnn @_";
	$self->{pool} = [
		map { AnyEvent::DBD::Pg->new($dsn,$user,$pass,$args,@args,id => $_) } 1..$count
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
	$_->connect(@_) for @{ $self->{pool} };
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = shift;
	my $cb = pop;
	my @args = @_;
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;
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
	$self->take(sub {
		my $db = shift;
		$db->begin_work(sub {
			my $wr = AnyEvent::DBD::Pool::Tx->new($db, sub {
				my $wr = shift;
				if ($wr->{commited}) {
					$self->ret($db);
				} else {
					my $call = $args{default};
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
	#warn("take wrk, left ".$#{$self->{pool}}." for @{[(caller)[1,2]]}\n");
	if (@{$self->{pool}}) {
		my $db = shift @{$self->{pool}};
		$db->{_return_to_me} = $self;
		$cb->($db);
	} else {
		#warn("no worker for @{[(caller 1)[1,2]]}, maybe increase pool?");
		push @{$self->{waiting_db}},$cb
	}
}

sub ret {
	my $self = shift;
	delete $_->{_return_to_me} for @_;
	push @{ $self->{pool} }, @_;
	$self->take(shift @{ $self->{waiting_db} }) if @{ $self->{waiting_db} };
}


1;

