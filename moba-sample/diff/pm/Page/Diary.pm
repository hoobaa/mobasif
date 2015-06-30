package Page::Diary;

use strict;
use MobaConf;
use HTMLTemplate;
use Common;
use Request;
use Response;
use DA;
use Kcode;

use Func::User;
use Func::RemoteQueue;

#-----------------------------------------------------------
# 日記一覧（指定ユーザ）

sub pageDiaryList {
	my $func = shift;
	my $rhData  = Common::cloneHash($_::F, '^[a-z]');
	my $rhData2 = {};
	
	$rhData->{p} = ($rhData->{p} >  1) ? int($rhData->{p}) : 1;
	
	my $ipp = 5;
	my $from = ($rhData->{p} - 1) * $ipp;
	my $ipp2 = $ipp + 1;
	
	if ($rhData->{u} == $_::U->{USER_ID}) {
		$rhData2->{CanAdm} = 1;
	}
	
	# ニックネーム取得
	
	Func::User::addUserInfo($rhData, 'u', 'nickname');
	if (!$rhData->{nickname}) {
		MException::throw({ CHG_FUNC => '.404' });
	}
	
	# リスト取得
	
	my $dbh = DA::getHandle($_::DB_DIARY_R);
	my $sth = $dbh->prepare(<<"SQL");
	select
		diary_id, user_id, post_date, subject, content,
		comment_num, access_num
	from diary_data where user_id=?
	order by post_date desc limit $from, $ipp2
SQL
	$sth->execute($rhData->{u});
	
	my $rows = $sth->rows;
	my @List;
	while (my $rHash = $sth->fetchrow_hashref()) {
		_makeDiaryContent($rHash, 400);
		push(@List, $rHash);
		last if (scalar(@List) == $ipp);
	}
	if (scalar(@List)) {
		$List[$#List]->{Last} = 1;
		$rhData->{List} = \@List;
	}
	
	# ページング
	
	if ($rhData->{p} > 1) {
		$rhData->{PrevPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} - 1,
				u => $rhData->{u},
			});
	}
	if ($rows == $ipp2) {
		$rhData->{NextPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} + 1,
				u => $rhData->{u},
			});
	}
	
	my $html = HTMLTemplate::insert(
		"diary/dia_list", $rhData, $rhData2);
	Response::output(\$html);
}

#-----------------------------------------------------------
# 日記一覧（全体）
	
sub pageDiarySearch {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	$rhData->{p} = ($rhData->{p} >  1) ? int($rhData->{p}) : 1;
	$rhData->{p} = ($rhData->{p} < 100) ? int($rhData->{p}) : 100;
	
	my $ipp = 10;
	my $from = ($rhData->{p} - 1) * $ipp;
	my $ipp2 = $ipp + 1;
	
	# リスト取得
	
	my $dbh = DA::getHandle($_::DB_DIARY_R);
	my $sth = $dbh->prepare(<<"SQL");
	select diary_id, user_id, post_date, subject, comment_num, access_num
	from diary_data order by post_date desc limit $from, $ipp2
SQL
	$sth->execute();
	
	my $rows = $sth->rows;
	my @List;
	while (my $rHash = $sth->fetchrow_hashref()) {
		my @t = localtime($rHash->{post_date}); $t[5] += 1900; $t[4]++;
		$rHash->{PostDate} = Kcode::e2s(sprintf("%d月%d日", @t[4,3]));
		
		push(@List, $rHash);
		last if (scalar(@List) == $ipp);
	}
	if (scalar(@List)) {
		Func::User::addUserInfo(\@List, 'user_id', 'nickname');
		$List[$#List]->{Last} = 1;
		$rhData->{List} = \@List;
	}
	
	# ページング
	
	if ($rhData->{p} > 1) {
		$rhData->{PrevPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} - 1,
				d => $rhData->{d},
			});
	}
	if ($rows == $ipp2 && $rhData->{p} < 100) {
		$rhData->{NextPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} + 1,
				d => $rhData->{d},
			});
	}
	my $html = HTMLTemplate::insert('diary/dia_srch', $rhData);
	Response::output(\$html);
}

#-----------------------------------------------------------
# 日記詳細

sub pageDiaryView {
	my $func = shift;
	my $rhData  = Common::cloneHash($_::F, '^[a-z]');
	my $rhData2 = {};
	
	#-------------------------
	# 日記情報
	
	my $dbh = DA::getHandle($_::DB_DIARY_R);
	my $sth = $dbh->prepare(<<'SQL');
	select
		diary_id, user_id, post_date, subject, content,
		comment_num, access_num, last_user
	from diary_data where diary_id=?
SQL
	$sth->execute($rhData->{d});
	if (!$sth->rows) {
		MException::throw({ CHG_FUNC => '.404' });
	}
	Common::mergeHash($rhData, $sth->fetchrow_hashref());
	Func::User::addUserInfo($rhData, 'user_id', 'nickname');
	
	if ($rhData->{user_id} == $_::U->{USER_ID}) {
		$rhData2->{CanAdm} = 1;
	}
	
	_makeDiaryContent($rhData);
	
	#-------------------------
	# アクセス数更新
	
	if ($_::U->{USER_ID} &&
	    $_::U->{USER_ID} != $rhData->{last_user} &&
	    $_::U->{USER_ID} != $rhData->{user_id}) {
		
		# 個別のプロセスから更新すると負荷が高いので、
		# １サーバのキューにまとめて daemon で更新させる。
		
		my @t = localtime(); $t[5] += 1900; $t[4]++;
		my $now = sprintf(
			"%04d/%02d/%02d %02d:%02d:%02d", @t[5,4,3,2,1,0]);
		Func::RemoteQueue::queue_write('acc_diary', join("\t",
			$now, $_::HOST, int($_::U->{USER_ID}), int($rhData->{d})));
	}
	
	#-------------------------
	# コメント一覧
	
	$rhData->{p} = ($rhData->{p} > 1) ? int($rhData->{p}) : 1;
	
	my $ipp = 5;
	my $from = ($rhData->{p} - 1) * $ipp;
	my $ipp2 = $ipp + 1;
	
	# リスト取得
	
	my $dbh = DA::getHandle($_::DB_DIARY_R);
	my $sth = $dbh->prepare(<<"SQL");
	select comment_id, post_date, content, user_id
	from diary_comment where diary_id=?
	order by post_date desc limit $from, $ipp2
SQL
	$sth->execute($rhData->{d});
	
	my $rows = $sth->rows;
	my @List;
	while (my $rHash = $sth->fetchrow_hashref()) {
		_makeCommentContent($rHash);
		push(@List, $rHash);
		last if (scalar(@List) == $ipp);
	}
	if (scalar(@List)) {
		Func::User::addUserInfo(\@List, 'user_id', 'nickname');
		$List[$#List]->{Last} = 1;
		$rhData->{List} = \@List;
	}
	
	if ($rhData->{p} > 1) {
		$rhData->{PrevPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} - 1,
				d => $rhData->{d},
			});
	}
	if ($rows == $ipp2) {
		$rhData->{NextPageUrl} = "_$func?".
			Common::makeParams({
				p => $rhData->{p} + 1,
				d => $rhData->{d},
			});
	}
	
	my $html = HTMLTemplate::insert("diary/dia_view", $rhData, $rhData2);
	Response::output(\$html);
}

sub _makeDiaryContent {
	my ($rhData, $limit) = @_;
	if ($limit && length($rhData->{content}) > $limit) {
		$rhData->{content} =
			$_::MCODE->usub($rhData->{content}, $limit). "..";
		$rhData->{Continue} = 1;
	}
	my @t = localtime($rhData->{post_date}); $t[5] += 1900; $t[4]++;
	$rhData->{PostDate} = Kcode::e2s(sprintf("%d月%d日", @t[4,3]));
}

sub _makeCommentContent {
	my ($rhData) = @_;
	my @t = localtime($rhData->{post_date}); $t[5] += 1900; $t[4]++;
	$rhData->{PostDate} = sprintf("%04d/%d/%d %d:%02d", @t[5,4,3,2,1,0]);
}

#-----------------------------------------------------------
# 日記投稿

sub pageDiaryPost {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	my $dbh = DA::getHandle(
		$rhData->{exec} ? $_::DB_DIARY_W : $_::DB_DIARY_R);
	
	my $dir    = 'diary';
	my @params = ('subject', 'content');
	my @page   = ('dia_post1', 'dia_post2', 'dia_post3');
	
	my $step =
		($rhData->{exec})    ? 2 :
		($rhData->{confirm}) ? 1 : 0;
	my $page = $page[$step];
	
	if ($step == 0) {
		$rhData->{diary_id} = DA::getSequence('diary');
	}
	
	# 入力内容正規化
	
	for my $key (@params) {
		$rhData->{$key} =~ s/\s+$//mg;
		$rhData->{$key} =~ s/\r//g;
		$rhData->{$key} =~ s/\n+$//s;
	}
	
	# 内容チェック
	
	if ($step > 0) {
		_checkDiaryData($rhData);
		if (lc($ENV{REQUEST_METHOD}) ne 'post') {
			$rhData->{Err} = 1;
		}
		if ($rhData->{Err}) {
			$page = $page[0];
		}
	}
	
	# 確定処理
	
	if ($step == 2 && !$rhData->{Err}) {
		my $sth = $dbh->prepare(<<'SQL');
		insert ignore into diary_data (
			diary_id, user_id, post_date,
			subject, content, comment_num
		) values (?,?,?, ?,?,?)
SQL
		$sth->execute(
			$rhData->{diary_id}, $_::U->{USER_ID}, time(),
			$rhData->{subject}, $rhData->{content}, 0);
		
		if (!$sth->rows) {
			$rhData->{Err} = $rhData->{ErrDup} = 1;
		}
		DA::commit();
	}
	
	my $html = HTMLTemplate::insert("$dir/$page", $rhData);
	Response::output(\$html);
}

sub _checkDiaryData {
	my ($rhData, $max_content_length) = @_;
	
	if ($rhData->{subject} eq '') {
		$rhData->{Err} = $rhData->{ErrSubjectE} =1;
	}
	if (length($rhData->{subject}) > 40) {
		$rhData->{Err} = $rhData->{ErrSubjectL} =1;
	}
	if ($rhData->{content} eq '') {
		$rhData->{Err} = $rhData->{ErrContentE} =1;
	}
	if (length($rhData->{content}) > 2000) {
		$rhData->{Err} = $rhData->{ErrContentL} =1;
	}
}

#-----------------------------------------------------------
# 日記修正

sub pageDiaryMod {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	my $dbh_d = DA::getHandle(
		$rhData->{exec} ? $_::DB_DIARY_W : $_::DB_DIARY_R);
	
	my $dir    = 'diary';
	my @params = ('subject', 'content');
	my @page   = ('dia_mod1', 'dia_mod2', 'dia_mod3');
	
	my $step =
		($rhData->{exec})    ? 2 :
		($rhData->{confirm}) ? 1 : 0;
	my $page = $page[$step];
	
	# 入力内容正規化
	
	for my $key (@params) {
		$rhData->{$key} =~ s/\s+$//mg;
		$rhData->{$key} =~ s/\r//g;
		$rhData->{$key} =~ s/\n+$//s;
	}
	
	# 基本データ取得
	
	my $sth;
	if ($step == 0) {
		$sth = $dbh_d->prepare(<<'SQL');
		select diary_id, post_date, subject, content
		from diary_data where diary_id=? and user_id=?
SQL
	} else {
		$sth = $dbh_d->prepare(<<'SQL');
		select diary_id, post_date
		from diary_data where diary_id=? and user_id=?
SQL
	}
	$sth->execute($rhData->{d}, $_::U->{USER_ID});
	if (!$sth->rows) {
		die "diary_data not found ($rhData->{d},$_::U->{USER_ID})";
	}
	Common::mergeHash($rhData, $sth->fetchrow_hashref());
	
	# 内容チェック
	
	if ($step > 0) {
		_checkDiaryData($rhData);
		if (lc($ENV{REQUEST_METHOD}) ne 'post') {
			$rhData->{Err} = 1;
		}
		if ($rhData->{Err}) {
			$page = $page[0];
		}
	}
	
	# 確定処理
	
	if ($step == 2 && !$rhData->{Err}) {
		my $sth = $dbh_d->prepare(<<'SQL');
		update diary_data set subject=?, content=? where diary_id=?
SQL
		$sth->execute(
			$rhData->{subject}, $rhData->{content}, $rhData->{d});
		DA::commit();
	}
	my $html = HTMLTemplate::insert("$dir/$page", $rhData);
	Response::output(\$html);
}

#-----------------------------------------------------------
# コメント投稿

sub pageCommentPost {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	my $dbh_d = DA::getHandle(
		$rhData->{exec} ? $_::DB_DIARY_W : $_::DB_DIARY_R);
	
	my $dir    = 'diary';
	my @params = ('content');
	my @page   = ('cmt_post1', 'cmt_post2', 'cmt_post3');
	
	my $step =
		($rhData->{exec})    ? 2 :
		($rhData->{confirm}) ? 1 : 0;
	my $page = $page[$step];
	
	if ($step == 0) {
		$rhData->{comment_id} = DA::getSequence('comment');
	}
	
	# 基本データ取得
	
	my $sth = $dbh_d->prepare(<<'SQL');
	select user_id from diary_data where diary_id=?
SQL
	$sth->execute($rhData->{d});
	if (!$sth->rows) {
		die "diary_data not found ($rhData->{d})";
	}
	Common::mergeHash($rhData, $sth->fetchrow_hashref());
	
	# 入力内容正規化
	
	for my $key (@params) {
		$rhData->{$key} =~ s/\s+$//mg;
		$rhData->{$key} =~ s/\r//g;
		$rhData->{$key} =~ s/\n+$//s;
	}
	
	# 内容チェック
	
	if ($step > 0) {
		_checkCommentData($rhData);
		if (lc($ENV{REQUEST_METHOD}) ne 'post') {
			$rhData->{Err} = 1;
		}
		if ($rhData->{Err}) {
			$page = $page[0];
		}
	}
	
	# 確定処理
	
	if ($step == 2 && !$rhData->{Err}) {
		my $sth = $dbh_d->prepare(<<'SQL');
		insert ignore into diary_comment (
			comment_id, diary_id, diary_user,
			post_date, user_id, content
		) values (?,?,?, ?,?,?)
SQL
		$sth->execute(
			$rhData->{comment_id}, $rhData->{d}, $rhData->{user_id},
			time(), $_::U->{USER_ID}, $rhData->{content});
		
		if ($sth->rows) { # コメント数の更新
			my $sth = $dbh_d->prepare(<<'SQL');
			update diary_data set comment_num=comment_num+1 where diary_id=?
SQL
			$sth->execute($rhData->{d});
			
		} else {
			$rhData->{Err} = $rhData->{ErrDup} = 1;
		}
		DA::commit();
	}
	
	my $html = HTMLTemplate::insert("$dir/$page", $rhData);
	Response::output(\$html);
}
sub _checkCommentData {
	my ($rhData) = @_;
	
	if ($rhData->{content} eq '') {
		$rhData->{Err} = $rhData->{ErrContentE} =1;
	}
	if (length($rhData->{content}) > 400) {
		$rhData->{Err} = $rhData->{ErrContentL} =1;
	}
}

#-----------------------------------------------------------
# 日記削除

sub pageDiaryDel {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	my $dbh_d = DA::getHandle(
		$rhData->{exec} ? $_::DB_DIARY_W : $_::DB_DIARY_R);
	
	# チェック
	
	my $msg_st = 0;
	if ($rhData->{exec}) {
		
		# 権限確認
		
		my $sth = $dbh_d->prepare(<<'SQL');
		select user_id, diary_id, post_date, subject, content
		from diary_data where diary_id=?
SQL
		$sth->execute($rhData->{d});
		if (!$sth->rows) {
			MException::throw({ CHG_FUNC => '.404' });
		}
		Common::mergeHash($rhData, $sth->fetchrow_hashref());
		if (!$rhData->{user_id} == $_::U->{USER_ID}) {
			die "not owner ($rhData->{d},$_::U->{USER_ID})";
		}
	}
	
	# 処理実行
	
	if ($rhData->{exec} && !$rhData->{Err}) {
		if (lc($ENV{REQUEST_METHOD}) ne 'post') {
			$rhData->{Err} = 1;
		}
		
		# 日記削除
		
		my $sth = $dbh_d->prepare(<<"SQL");
		delete from diary_data where diary_id=?
SQL
		$sth->execute($rhData->{d});
		
		# コメント削除
		
		my $sth = $dbh_d->prepare(<<"SQL");
		delete from diary_comment where diary_id=?
SQL
		$sth->execute($rhData->{d});
		
		$rhData->{Done} = 1;
		DA::commit();
	}
	
	my $html = HTMLTemplate::insert('diary/dia_del', $rhData);
	Response::output(\$html);
}

#-----------------------------------------------------------
# コメント削除

sub pageCommentDel {
	my $func = shift;
	my $rhData = Common::cloneHash($_::F, '^[a-z]');
	
	my $dbh_d = DA::getHandle(
		$rhData->{exec} ? $_::DB_DIARY_W : $_::DB_DIARY_R);
	
	# チェック
	
	if ($rhData->{exec}) {
		if (lc($ENV{REQUEST_METHOD}) ne 'post') {
			die "bad request";
		}
		my $sth = $dbh_d->prepare(<<'SQL');
		select diary_id from diary_comment
		where comment_id=? and diary_user=?
SQL
		$sth->execute($rhData->{c}, $_::U->{USER_ID});
		if (!$sth->rows) {
			die "not owner ($rhData->{d},$_::U->{USER_ID})";
		}
		($rhData->{diary_id}) = $sth->fetchrow_array();
	}
	
	# 処理実行
	
	if ($rhData->{exec} && !$rhData->{Err}) {
		my $sth = $dbh_d->prepare(<<"SQL");
		delete from diary_comment where comment_id=?
SQL
		$sth->execute($rhData->{c});
		
		if ($sth->rows) {
			my $sth = $dbh_d->prepare(<<"SQL");
			update diary_data set comment_num=comment_num-1 where diary_id=?
SQL
			$sth->execute($rhData->{diary_id});
		}
		DA::commit();
		$rhData->{Done} = 1;
	}
	
	my $html = HTMLTemplate::insert('diary/cmt_del', $rhData);
	Response::output(\$html);
}

1;
