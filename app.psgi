#!/usr/bin/perl
use 5.014; use warnings;

use Git::Raw ();
use HTTP::Date 'time2str';
use Plack::MIME ();
use Plack::Middleware::ConditionalGET ();
use Plack::Middleware::Deflater ();

my $git = Git::Raw::Repository->open( $ENV{'GIT_DIR'} // '.' );

my ( $prev_commit, $date ) = '';

my $app = sub {
	my $meth = $_[0]{'REQUEST_METHOD'};
	return [ 405, [], [] ] if 'GET' ne $meth and 'HEAD' ne $meth;

	my $raw_path = $_[0]{'PATH_INFO'} // '/';
	my $path = $raw_path =~ s!/\K(?:\.?/)*!!gr; # collapse double slashes
	$path =~ s!\A/!! if $raw_path =~ s!\A/!!;

	return [ 404, [], [] ] if '/' eq substr $path, -1;

	my $commit = $git->head->target;
	my $o = $commit->tree;
	my @p = split '/', $path, -1;
	while ( @p ) {
		my $sub_o = ( $o->entry_byname( shift @p ) or last )->object;
		last if @p and $sub_o->is_blob;
		$o = $sub_o;
	}

	return [ 404, [], [] ] if @p or $o->is_tree;
	return [ 303, [ Location => "$_[0]{'SCRIPT_NAME'}/$path" ], [] ] if $path ne $raw_path;

	$date = time2str $commit->time, $prev_commit = $commit->id if $prev_commit ne $commit->id;

	my $type = Plack::MIME->mime_type( $path ) // 'text/plain';
	$type .= ';charset=utf-8' if 'text/plain' eq $type;

	my $h = [
		'Content-Type'   => $type,
		'Content-Length' => $o->size,
		'ETag'           => '"'.$o->id.'"',
		'Last-Modified'  => $date,
		'Cache-Control'  => 'public',
	];

	[ 200, $h, [ 'HEAD' eq $meth ? () : $o->content ] ];
};

Plack::Middleware::Deflater->wrap( Plack::Middleware::ConditionalGET->wrap( $app ) );
