                   Vim version 7.2 香り屋版 導入マニュアル

                                                         Version: 1.4.0
                                                          Author: MURAOKA Taro
                                                           Since: 23-Aug-1999
                                                     Last Change: 01-Mar-2009.

概要
  Vimはviクローンに分類されるテキストエディタです。

  オリジナルのVimはhttp://www.vim.org/で公開されており、そのままでも日本語を含
  むテキストは編集できますが、香り屋では日本語をより扱い易くするための修正と追
  加を行い香り屋版として公開しています。

インストール方法
  配布ファイルは自己解凍書庫です。配布ファイルをダブルクリックすると解凍先を選
  択した後、Vimプログラムフォルダの解凍が始まります。Vimプログラムフォルダは好
  きな場所に配置することができます。

    配布ファイル: vim72-YYYYMMDD-kaoriya-w32j.exe
    Vimプログラムフォルダ: vim72-kaoriya-w32j

  上記のYYYYMMDDにはリリースの年月日が入ります。

実行方法
  Vimプログラムフォルダの中のgvimもしくはvimをダブルクリックしてください。初め
  ての起動の時にはレジストリ登録の可否を聞かれます。通常はYesを選択してくださ
  い。No選択すれば登録しないこともできますが、その場合は次回の起動時にも同様に
  聞かれます。

アンインストール (Windows)
  Vimをアンインストールするには、unregist.batをダブルクリックしてレジストリ登
  録を解除してから、Vimをインストールしたフォルダを削除してください。

初心者の方へ
  まずはVimの操作に慣れるためトレーニングすることをオススメします。1回のトレー
  ニングにかかる時間には個人差がありますが30分から1時間くらいです。トレーニン
  グを開始するにはVimを起動した後
    :Tutorial
  と入力してリターンキーを押します。あとは画面に表示された文章にしたがって操作
  することで、Vimの基本的な操作を練習することができます。慣れるまで何度か繰り
  返し練習するとより効果的です。

Vimの拡張機能について
  本章ではVimの拡張機能の紹介とインストール方法について述べます。拡張機能をイ
  ンストールしなくても、Vimを使うことはできます。

  漢字コード自動変換

    Vimではiconv.dllを利用する事で漢字コード(cp932/euc-jp/その他)を自動変換で
    きるようになります。iconv.dllは別途入手する必要があります。
    注意: iconv.dllをインストールしなくてもVimは使用できます。

    iconv.dllを正しくインストールし、Vimを再起動すれば自動的に機能が有効になり
    ます。iconv.dllのインストール方法はiconv.dllのドキュメントを参考にしてくだ
    さい。通常はVimプログラムフォルダにiconv.dll置いてください。

    iconv.dllはlibiconvをコンパイルしたもので以下のサイトで入手可能です。
    iconv.dllはlibiconvに従い、GNU LGPLに基づいて配布されています。

    - iconv.dll配布サイト (日本語ドキュメント有り)
        http://www.kaoriya.net/
    - libiconv開発サイト(Bruno Haible氏)
        http://sourceforge.net/cvs/?group_id=51585
        http://ftp.gnu.org/pub/gnu/libiconv/

  ローマ字による日本語検索
    Vimではmigemo.dllを利用することで、IMEを使わずにローマ字で直接、日本語の単
    語を検索できるようになります。この機能はMigemoという名前で知られています。
    migemo.dllのインストール法、及び使用法はmigemo.dllの配布パッケージに従って
    ください。
    注意: migemo.dllをインストールしなくてもVimは使用できます。

    - migemo.dll配布サイト (C/Migemo有り)
        http://www.kaoriya.net/#CMIGEMO
    - 本家Ruby/Migemo (Migemoに関する詳細)
        http://migemo.namazu.org/

  OLEとの連携
    香り屋版のVimはOLEに対応しています。始めて実行する時にはダイアログに英語で
    「レジストリにOLEを登録しますか?」と聞かれます。ここでYesを選択すればOLE登
    録が行なわれ、次回の起動以降同じことは聞かれません。Noを選択した場合は登録
    されず、次回起動時に同じことを聞かれます。アンインストールするなどの理由に
    より、一度登録したレジストリを削除する場合には、unregist.batをダブルクリッ
    クして実行してください。

  ctagsについて
    現在Vimはctagsを同梱していません。必要とする方は以下のサイトから各自入手し
    インストールしてください。

    - h_east's website (ctags日本語対応版バイナリ配布場所)
        http://hp.vector.co.jp/authors/VA025040/

    - ctagsオリジナルサイト
        http://ctags.sourceforge.net/

  Perl(ActivePerl)との連携
    注意: PerlをインストールしなくてもVimは使用できます。

    ActiveState社により公開されているActivePerl 5.8をインストールすることで、
    Perlインターフェースを使用することができます。ActivePerlをインストールして
    いない場合は、Perlインターフェースは自動的に無効となります。Perlインター
    フェースの詳細については":help perl"としてVim付属のマニュアルを参照してく
    ださい。

    - ActiveState社 (ActivePerl)
        http://www.activestate.com/

  Pythonとの連携
    注意: PythonをインストールしなくてもVimは使用できます。

    Python.orgにより公開されているPython 2.5をインストールすることで、Pythonイ
    ンターフェースを使用することができます。Pythonをインストールしていない場合
    は、Pythonインターフェースは自動的に無効となります。Pythonインターフェース
    の詳細については":help python"としてVim付属のマニュアルを参照してください。

    - Python.org
        http://www.python.org/

  Rubyとの連携
    注意: RubyをインストールしなくてもVimは使用できます。

    まつもとゆきひろ氏により開発されているRubyのmswin32版をインストールするこ
    とで、Rubyインターフェースを使用することができます。Rubyをインストールして
    いない場合は、Rubyインターフェースは自動的に無効となります。Rubyインター
    フェースの詳細についてはVimで":help ruby"を実行して、付属のマニュアルを参
    照してください。

    - Ruby-mswin32 配布サイト
        http://www.ruby-lang.org/ja/
        http://www.garbagecollect.jp/ruby/mswin32/ja/

    Windows版で利用するにはバージョン1.8.xのRubyをインストールしてください。

使用許諾
  香り屋版のライセンスはオリジナルのVimに従います。詳しくはREADME.txtをご覧下
  さい。

  Vimはチャリティーウェアと称していますが、オープンソースであり無料で使用する
  ことができます。しかしVimの利用に際して対価を支払いたいと考えたのならば、是
  非ウガンダの孤児達を援助するための寄付をお願いいたします。

  簡単な(無料の)寄付の方法
    海外からCDや本を注文する際に以下のリンクを経由して購入することで、その売上
    の何パーセントかが寄付されます。購入者には正規の代金以外の負担はありませ
    ん。洋書などが入用の際には、進んでご利用ください。

    - 買い物による寄付
      http://iccf-holland.org/click.html

  Vim開発スポンサー制度
    Vim開発スポンサー制度と機能要望投票制度が始まりました。有志がVimの開発にお
    金を出資しBram氏に開発へ専念してもらおうという主旨です。出資者には見返りに
    機能要望投票の権利が与えられます。最近ではfoldingがそうであったように、こ
    の機能要望投票で多くの票数を集めた機能から優先して実装されます。出資は1口
    10ユーロ以上からで、PayPalを通じてクレジットカードによる決済も可能です。ま
    た寄付した事実が公表されることを拒まなければ、100ユーロ以上寄付をした場合
    には「Hall of honour」に掲載されます。詳細は以下のURLを参照してください。

    - Sponsor Vim development
      http://www.vim.org/sponsor/index.php

オリジナルとの相違点
  ソース差分
    patchesフォルダ内に同梱しています。差分の使い方や内容に関する質問やコメン
    トなどありましたら香り屋版メンテナまで連絡ください。ソース1行1行に至るまで
    の検証も大歓迎します。

既知の問題点
  * qkcの-njフラグでコンバートしたJISファイルは開けない(iconv.dll)
  * scrolloffが窓高の丁度半分の時、スクロールが2行単位になる
  * 書き込み時にNTFSのハードリンクが切れる

質問・連絡先
  Vim用の掲示板が用意されています。どんなに簡単なことでもわからないことがあ
  るのならばここで聞いてみると良いでしょう。きっと何らかの助けにはなるはずで
  す。もちろんメールで香り屋版メンテナに直接聞いてもらっても構いません。

  日本語化部分などの不都合は香り屋版メンテナまで連絡をいただければ、折をみて修
  正いたします。Vim本体に属すると思われる不都合については、直接
  Vim本家の
  ほうへ英語で連絡するか、香り屋版メンテナに問い合わせてください。応急的に
  処置できるものであればそうしますし、そうでなくても後日つたない英語になります
  がVim本家へフィードバックできるかもしれません。Vim日本語版等
  の関連情報は次のURLにあります。

  - Vim本家
      http://www.vim.org/
  - Vim日本語版情報
      http://www.kaoriya.net/#VIM
  - Vim掲示板
      http://www.kaoriya.net/bbs/bbs.cgi
  - 香り屋版メンテナ
      MURAOKA Taro <koron@tka.att.ne.jp>

謝辞
  何よりも、素晴らしいエディタであるVimをフリーソフトウェアとして公開&管理し、
  今回の日本語版の公開を快諾していただいたBram Moolenaar氏に最大の感謝をいたし
  ます。また、この配布パッケージには以下の方々によるファイル・ドキュメントが含
  まれています。加えて香り屋版の作成に関連して、多くの方いから様々なアイデアや
  バグ報告をいただきました。皆様協力ありがとうございます。

  (アルファベット順)
  - 215 (Vim掲示板:1587)
    autodate.vimの英語ドキュメント添削
  - FUJITA Yasuhiro <yasuhiroff@ka.baynet.ne.jp>
    runtime/keymap/tcode_cp932.vim (マップ修正・追加)
  - KIHARA, Hideto <deton@m1.interq.or.jp>
    runtime/keymap/tutcode_cp932.vim
  - MATSUMOTO Yasuhiro <mattn_jp@hotmail.com>
    diffs/ (一部コード流用/アドバイス/遊び仲間)
  - NISHIOKA Takuhiro <takuhiro@super.win.ne.jp>
    runtime/plugin/format.vim (Vim6対応改造版)
  - TAKASUKA Yoshihiro <tesuri@d1.dion.ne.jp>
    runtime/keymap/tcode_cp932.vim

  そして総てのVimユーザに。

------------------------------------------------------------------------------
                  生きる事への強い意志が同時に自分と異なる生命をも尊ぶ心となる
                                            MURAOKA Taro <koron@tka.att.ne.jp>
 vim:set ts=8 sts=2 sw=2 tw=78 et ft=memo:
