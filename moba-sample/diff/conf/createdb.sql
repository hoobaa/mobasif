grant all privileges on *.* to ###PROJ_NAME###_w@"%";
grant all privileges on *.* to ###PROJ_NAME###_w@"localhost";
grant select         on *.* to ###PROJ_NAME###_r@"%";
grant select         on *.* to ###PROJ_NAME###_r@"localhost";

#---------------------------------------------------------------------
# user db

drop   database if exists ###PROJ_NAME###_user;
create database           ###PROJ_NAME###_user;
use                       ###PROJ_NAME###_user;

create table user_data (
  user_id       int         unsigned not null, # ユーザID
  reg_date      int         unsigned not null, # 登録日時
  user_st       tinyint              not null, # ユーザステータス
  serv_st       tinyint              not null, # サービスステータス
  
  carrier       char(1)              not null, # キャリア ( D | A | V )
  model_name    varchar(20)          not null, # 現在の機種名
  subscr_id     varchar(40)                  , # サブスクライバID
  serial_id     varchar(30)                  , # SIMカード / 端末ID
  
  nickname      varchar(16)          not null, # ニックネーム
  sex_type      char(1)              not null, # M | F
  birthday      date                 not null, # 生年月日
  intro         text                 not null, # 自己紹介
  blood_type    varchar(2)           not null, # A | B | O | AB
  show_birth    tinyint              not null, # 誕生日を見せる
  show_age      tinyint              not null  # 年齢をみせる

) type=InnoDB;

alter table user_data
 add primary key     (user_id),
 add unique index i1 (subscr_id),
 add unique index i2 (serial_id),
 add unique index i3 (nickname);

#---------------------------------------------------------------------
# sequence db

drop   database if exists ###PROJ_NAME###_seq;
create database           ###PROJ_NAME###_seq;
use                       ###PROJ_NAME###_seq;

create table seq_user (id int unsigned not null) type=MyISAM;
insert into  seq_user values (10000);

create table seq_diary (id int unsigned not null) type=MyISAM;
insert into  seq_diary values (10000);

create table seq_comment (id int unsigned not null) type=MyISAM;
insert into  seq_comment values (10000);

#---------------------------------------------------------------------
# diary db

drop   database if exists ###PROJ_NAME###_diary;
create database           ###PROJ_NAME###_diary;
use                       ###PROJ_NAME###_diary;

create table diary_data (
diary_id    int unsigned not null, # 日記ID
user_id     int unsigned not null, # ユーザID
post_date   int unsigned not null, # 日記日時
subject     varchar(100) not null, # タイトル
content     text         not null, # 内容
comment_num smallint     not null, # コメント数
access_num  int unsigned not null, # アクセス数
last_user   int unsigned not null  # 最終アクセスユーザ
);
alter table diary_data
  add primary key (diary_id),
  add index i1 (user_id, post_date),
  add index i2 (post_date),
  add index i3 (comment_num),
  add index i4 (access_num);

create table diary_comment (
comment_id int unsigned not null, # コメントID
diary_id   int unsigned not null, # 日記ID
diary_user int unsigned not null, # 日記ユーザID
post_date  int unsigned not null, # コメント日時
user_id    int unsigned not null, # コメント者ID
content    text         not null  # コメント内容
);
alter table diary_comment
  add primary key (comment_id),
  add index i1 (diary_id,   post_date),
  add index i2 (diary_user, post_date),
  add index i3 (user_id,    post_date);

