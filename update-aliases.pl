#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use Data::Dumper;
use MyConfig;
use MyLogger;
use Node;

my $log = MyLogger->get_logger();

my @ids = @ARGV;

my $dsn =
  "DBI:mysql:database=" . config('dbname') . ';host=' . config('dbhost');
my $dbh = DBI->connect($dsn, config('dbuser'), config('dbpass'))
  or $log->logdie($DBI::errstr);
my $insert_alias_sth =
  $dbh->prepare("INSERT INTO "
	  . config('dbprefix')
	  . "url_alias (source, alias, language) VALUES (?, ?, ?)")
  or $log->die($dbh->errstr);

for my $id (@ids)
{
# 	my $book = Node->new(obj => { identifier => $id } );
# 	my $node_path  = "node/" . $book->nid();
# 	my $node_alias = "books/$id";
# 	mkalias($node_path, $node_alias, "book");

	my $nodeids = Node::get_page_nodeids($id);

	$log->debug(Dumper($nodeids));

# 	for my $pageno (sort {$a <=> $b} keys %{$nodeids})
# 	{
# 		my $nid = $nodeids->{$pageno};
# 		$log->debug("nid page[$pageno]: $nid");
# 		
# 		my $node_path  = "node/$nid";
# 		my $node_alias = "books/$id/$pageno";
# 		mkalias($node_path, $node_alias, "page");
# 	}

	mkalias("node/$nodeids->{1}", ");

}


$insert_alias_sth->finish;
$dbh->disconnect;


sub mkalias
{
	my ($src, $dst, $type) = @_;
	$log->debug("Creating $type src=$src dst=$dst");
# 	$insert_alias_sth->execute($src, $dst, 'en');
}


