	use common::sense 3;
	use lib::abs '../lib';
	use EV;
	
	use AnyEvent::DBD::Pool;
	
	my $adb = AnyEvent::DBD::Pool->new(3, 'dbi:Pg:dbname=bot', bot => '', {
		pg_enable_utf8 => 1,
		pg_server_prepare => 0,
		quote_char => '"',
		name_sep => ".",
	}, debug => 1);
	
	$adb->queue_size( 4 );
	$adb->debug( 1 );
	
	$adb->connect;
	$adb->txn(sub {
		my $db = shift;
	});
	$adb->txn(sub {
		my $db = shift;
		$db->selectrow_array("select 1",sub {
			$db->commit; # optional
		});
	});
	$adb->txn(default => 'rollback',sub {
		my $db = shift;
		$db->selectrow_array("select 3",sub {
			$db->commit;
		});
	});
	$adb->txn(sub {
		my $db = shift;
		$db->selectrow_array("select 3",sub {
			#$db->commit;
		});
	});
	AE::cv->recv;
