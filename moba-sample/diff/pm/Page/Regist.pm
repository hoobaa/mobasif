package Page::Regist;

use Time::Local;

use strict;
use MobaConf;
use HTMLTemplate;
use Common;
use Response;
use DA;
use Kcode;

use Func::User;

#---------------------------------------------------------------------
# 会員登録

sub pageMain {
	my $func = shift;
	my $from = $_::F->{p};
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	$func = 'r01' if ($rhData->{mod_r01});
	my $page = $func;
	
	normalizeData($rhData);
	
	if ($from eq 'r00') {
		setInitialData($rhData);
	}
	
	if ($_::U->{USER_ID}) {
		$page = 'r04_2'; # 登録済み
	} else {
		if (my $ret = checkData($rhData, $from, $page)) {
			$page = $ret;
		} elsif ($func eq 'r04') {
			registerUser($rhData);
			DA::commit();
		}
		# 表示用データ生成
		$rhData->{birthday} = $rhData->{bymd};
		Func::User::makeProfile($rhData);
	}
	
	my $html = HTMLTemplate::insert("regist/$page", $rhData);
	Response::output(\$html);
}

sub registerUser {
	my ($rhData) = @_;
	
	my $user_id = DA::getSequence('user');
	
	#-----------
	# user_data
	
	my $dbh = DA::getHandle($_::DB_USER_W);
	my $sth = $dbh->prepare(<<'SQL');
		insert into user_data (
		user_id, reg_date, user_st, serv_st, 
		carrier, model_name, subscr_id, serial_id,
		
		nickname, sex_type, birthday,
		intro, blood_type, show_birth, show_age
		) values (
		?,?,?,?, ?,?,?,?, ?,?,?, ?,?,?,?)
SQL
	$sth->execute(
		$user_id, time(), 1, 0,
		
		$ENV{MB_CARRIER_UA}, $ENV{MB_MODEL_NAME},
		$ENV{MB_UID}    ? $ENV{MB_UID}    : undef,
		$ENV{MB_SERIAL} ? $ENV{MB_SERIAL} : undef,
		
		$rhData->{nn}, $rhData->{sex},
		sprintf("%04d-%02d-%02d",
			substr($rhData->{bymd}, 0, 4),
			substr($rhData->{bymd}, 4, 2),
			substr($rhData->{bymd}, 6, 2)),
		
		$rhData->{intro}, $rhData->{blood_type},
		int($rhData->{show_birth}),
		int($rhData->{show_age}));
	
	$_::U->{USER_ID} = $user_id;
	
	return($user_id);
}

#-----------------------------
# デフォルト値をセット

sub setInitialData {
	my ($rhData) = @_;
	
	$rhData->{bymd}       = '19';
	$rhData->{sex}        = '';
	$rhData->{show_birth} = 1;
	$rhData->{show_age}   = 1;
}

#-----------------------------
# 入力文字列の正規化

sub normalizeData {
	my $rhData = shift;
	my $spc = Kcode::e2s('　');
	
	for my $key (qw(bymd)) {
		$rhData->{$key} = $_::MCODE->u2any($rhData->{$key}, 'H');
	}
	
	for my $key (qw(bymd nn intro)) {
		$rhData->{$key} =~ s/\s+$//mg;
		$rhData->{$key} =~ s/\r//g;
		$rhData->{$key} =~ s/\n+$//s;
	}
	
	$rhData->{nn} =~ s/^($spc|\s)+//;
	$rhData->{nn} =~ s/($spc|\s)+$//;
	$rhData->{nn} =~ s/($spc|\s)+/ /g;
}

#-----------------------------
# 入力データチェック

sub checkData {
	my ($rhData, $from, $func) = @_;
	
	if ($from eq 'r01') {
		checkFormData1($rhData);
		return 'r01' if ($rhData->{Err});
		
	} elsif ($from eq 'r02') {
		checkFormData2($rhData);
		return 'r02' if ($rhData->{Err});
	}
	if ($func eq 'r04') {
		if ($ENV{MB_CARRIER_UA} eq 'D' && !$ENV{MB_SERIAL}) {
			$rhData->{Err} = $rhData->{ErrSerial} = 1;
		}
		return 'r03' if ($rhData->{Err});
		checkFormData2($rhData);
		return 'r02' if ($rhData->{Err});
		checkFormData1($rhData);
		return 'r01' if ($rhData->{Err});
	}
	return '';
}

sub checkFormData1 {
	my $rhData = shift;
	
	if ($rhData->{sex} !~ /^(M|F)$/) {
		$rhData->{Err} = $rhData->{ErrSexE} = 1;
	}
	
	if ($rhData->{bymd} =~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
		my @t1 = (localtime())[5,4,3]; $t1[0] += 1900; $t1[1]++;
		my @t2 = ($1, $2, $3);
		unless (_isValidDate($t2[0], $t2[1], $t2[2])) {
			$rhData->{Err} = $rhData->{ErrBirthV} = 1;
		}
		my $age = ($t1[0] - $t2[0]) -
			(($t1[1] * 100 + $t1[2] < $t2[1] * 100 + $t2[2]) ? 1 : 0);
		if ($age <= 0) {
			$rhData->{Err} = $rhData->{ErrBirthV} = 1;
		}
	} else {
		$rhData->{Err} = $rhData->{ErrBirthL} = 1;
	}
	
	if (my $res = _checkNickname($rhData->{nn})) {
		$rhData->{Err} = $rhData->{ErrNicknameE}     = 1 if ($res == -1);
		$rhData->{Err} = $rhData->{ErrNicknameL}     = 1 if ($res == -2);
		$rhData->{Err} = $rhData->{ErrNicknameEmoji} = 1 if ($res == -3);
		$rhData->{Err} = $rhData->{ErrNicknameDup}   = 1 if ($res == -9);
	}
}
sub _isValidDate {
	my ($y, $m, $d) = @_;
	eval {
		timelocal(0,0,0,$d,$m-1,$y);
	};
	return($@ ? 0 : 1);
}
sub _checkNickname {
	my ($nickname) = @_;
	
	return(-1) if (length($nickname) == 0);
	return(-2) if (length($nickname) > 12);
	return(-3) if ($_::MCODE->checkEmoji($nickname));
	
	my $dbh = DA::getHandle($_::DB_USER_W);
	my $sth = $dbh->prepare(<<'SQL');
	select user_id from user_data where nickname=? limit 1
SQL
	$sth->execute($nickname);
	return(-9) if ($sth->rows);
	
	return(0);
}

sub checkFormData2 {
	my $rhData = shift;
	
	if ($rhData->{blood_type} !~ /^A|B|O|AB$/) {
		$rhData->{Err} = $rhData->{ErrBloodE} =1;
	}
	if ($rhData->{intro} eq '') {
		$rhData->{Err} = $rhData->{ErrIntroE} =1;
	}
	if (length($rhData->{intro}) > 400) {
		$rhData->{Err} = $rhData->{ErrIntroL} =1;
	}
}

1;
