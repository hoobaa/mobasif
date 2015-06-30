package Page::User;

use strict;
use MobaConf;
use Common;
use HTMLTemplate;
use Response;
use DA;

use Func::User;

#-----------------------------------------------------------
# プロフィールページ

sub pageMain {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	if ($rhData->{u} == 0) {
		$rhData->{u} = $_::U->{USER_ID};
	}
	if ($rhData->{u} == $_::U->{USER_ID}) {
		$rhData->{SelfUser} = 1;
	}
	my $dbh = DA::getHandle($_::DB_USER_R);
	my $sth = $dbh->prepare(<<'SQL');
	select
		user_id, nickname,
		sex_type, birthday, intro,
		blood_type, show_birth, show_age
	from user_data where user_id=?
SQL
	$sth->execute($rhData->{u});
	
	if ($sth->rows) {
		Common::mergeHash($rhData, $sth->fetchrow_hashref());
		Func::User::makeProfile($rhData);
	} else {
		MException::throw( { CHG_FUNC => '.404' } );
	}
	my $html = HTMLTemplate::insert("user/u", $rhData);
	Response::output(\$html);
}

1;
