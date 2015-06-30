
■内容

このサンプルには、下記機能が入っています。

・会員登録
・日記の投稿・修正・閲覧・削除
・静的ページ

■使い方

MobaSiF インストール後、下記で差分をあててください。

rsync -avb --suffix=.orig diff/ $MOBA_DIR/

cd $MOBA_DIR/conf
find . -type f | xargs sed -i s:###MOBA_DIR###:$MOBA_DIR:g;
find . -type f | xargs sed -i s/###PROJ_NAME###/{DB基本名}/g;
find . -type f | xargs sed -i s/###USER###/$USER/g;
find . -type f | xargs sed -i s/###GROUP###/{実行GROUP}/g;
find . -type f | xargs sed -i s/###DOMAIN###/{web サーバのドメイン}/g;

cat createdb.sql | mysql -uroot

↑DB は drop database してから再作成されるので注意してください。

compile_template --refresh
