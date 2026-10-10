#!/usr/bin/env perl
# Reads for tests/release.sh what a shell reads badly: a manifest and a lockfile, which are
# JSON however they are laid out.
#   perl tests/release.pl manifest <packmoji.json>   name=<the package's name> and version=<its version>
#   perl tests/release.pl lock <packmoji.lock>       <name> <version> <sha256> for each locked package
use strict;
use warnings;
use Encode qw(encode_utf8);
use JSON::PP;

my ($mode, $file) = @ARGV;
$mode //= '';
if (($mode ne 'manifest' && $mode ne 'lock') || !defined $file) {
    print STDERR "usage: release.pl manifest <packmoji.json> | lock <packmoji.lock>\n";
    exit 2;
}

# A value that is a text and nothing else, on one line. Both files are someone's, and what
# one holds under a key may be anything.
sub text {
    my ($value) = @_;
    return '' if !defined $value || ref $value;
    $value =~ s/\s/ /g;
    return $value;
}

# One field of a line: a text with no space in it, and a dash where there is none.
sub field {
    my $value = text($_[0]);
    $value =~ s/ /_/g;
    return $value eq '' ? '-' : $value;
}

sub object {
    my ($value) = @_;
    return ref $value eq 'HASH' ? $value : {};
}

open(my $in, '<:raw', $file) or do { print "unreadable=it cannot be opened\n"; exit 0 };
my $bytes = do { local $/; <$in> } // '';
close($in);
# Packmoji leaves a byte order mark at the start out of account, and so does this.
$bytes =~ s/^\xEF\xBB\xBF//;
my $read = eval { JSON::PP->new->utf8->decode($bytes) };
if (ref $read ne 'HASH') { print "unreadable=it is not a JSON object\n"; exit 0 }

if ($mode eq 'manifest') {
    my $package = object($read->{package});
    print encode_utf8('name=' . text($package->{name}) . "\n" . 'version=' . text($package->{version}) . "\n");
    exit 0;
}

my $packages = ref $read->{packages} eq 'ARRAY' ? $read->{packages} : [];
for my $entry (@$packages) {
    my $locked = object($entry);
    print encode_utf8(join(' ', map { field($locked->{$_}) } qw(name version sha256))), "\n";
}
exit 0;
