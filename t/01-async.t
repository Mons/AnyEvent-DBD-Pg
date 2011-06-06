#!/usr/bin/env perl

use common::sense;
use uni::perl ':dumper';
use lib::abs '../lib';
use Test::More;
use AnyEvent::DBD::Pg;
use DBI;

my @args = ('dbi:Pg:dbname=test', user => '', {
	pg_enable_utf8 => 1,
	pg_server_prepare => 0,
	quote_char => '"',
	name_sep => ".",
});

eval {
	local $args[-1]{RaiseError} = 1;
	my $dbi = DBI->connect(@args);
	warn $dbi;
	$dbi->disconnect;
	1;
} or plan skip_all => "No test DB";

plan tests => 10;
my $cv = AE::cv;

my $adb = AnyEvent::DBD::Pg->new( @args, debug => 0);
my $ticks = 0;
my $t;$t = AE::timer 0.1,0.1, sub {
	$t;
		++$ticks;
};

$adb->begin_work(sub {
	ok shift(), 'begin';
	$adb->selectcol_arrayref("select pg_sleep( 1 ), 42", { Columns => [ 1 ] }, sub {
		my $rc = shift or warn;
		is $rc, 1, 'rc ok';
		my $res = shift;
		is $res->[0][0],42, 'res ok';
		cmp_ok $ticks, '>=', 9, 'have at least 9 tecks';
		diag "ticks: $ticks";
		$adb->commit(sub {
			ok shift(), 'commit';
			$cv->send;
		});
	});
});

$cv->recv;

__END__

	use common::sense 3;
	use lib::abs '../..';
	use EV;
	use AnyEvent::DBD::Pg;
	
	my $adb = AnyEvent::DBD::Pg->new(, debug => 1);
	
	$adb->queue_size( 4 );
	$adb->debug( 1 );
	
	$adb->connect;
	
	my $t;$t = AE::timer 0.5,0.5, sub {
		$t; warn "I'm alive: $t";
	};
	
	sub call;sub call {
		$adb->begin_work(sub {
			$adb->selectcol_arrayref("select pg_sleep( 1 ), 1", { Columns => [ 1 ] }, sub {
				my $rc = shift or return warn;
				my $res = shift;
				$adb->commit(sub {
					my $af;$af = AE::timer 0.1,0,sub {
						call();
						undef $af;
					};
				})
			});
			
		});
	}
	my $x; $x = AE::timer 2,0,sub {
		call();
		undef $x;
	};
	
	
	AE::cv->recv;
