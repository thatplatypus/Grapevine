#!/usr/bin/env perl
# Reads for tests/packages.sh what a shell reads badly: a manifest, which is JSON however it
# is laid out, and the includes of an Emojicode source, whose signs are not single bytes and
# need not have a plain space between them.
#   perl tests/packages.pl manifest <packmoji.json>   what the check asks of a manifest, a line each
#   perl tests/packages.pl includes <source>...       <source>:<line>:<path> for each file a source includes
use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8);
use JSON::PP;

my $mode = shift @ARGV // '';

# A value that is a text and nothing else. A manifest is someone's file, and what it holds
# under a key may be anything.
sub text {
    my ($value) = @_;
    return '' if !defined $value || ref $value;
    $value =~ s/[\r\n]/ /g;
    return $value;
}

sub list {
    my ($value) = @_;
    return '' if ref $value ne 'ARRAY';
    return join(', ', map { text($_) } @$value);
}

sub section {
    my ($value) = @_;
    return ref $value eq 'HASH' ? $value : {};
}

if ($mode eq 'manifest') {
    my $file = shift @ARGV // '';
    open(my $in, '<:raw', $file) or do { print "unreadable=it cannot be opened\n"; exit 0 };
    my $bytes = do { local $/; <$in> };
    close($in);
    # Packmoji leaves a byte order mark at the start out of account, and so does this.
    $bytes =~ s/^\xEF\xBB\xBF//;
    my $manifest = eval { JSON::PP->new->utf8->decode($bytes) };
    if (ref $manifest ne 'HASH') { print "unreadable=it is not a JSON object\n"; exit 0 }
    my $build = section($manifest->{build});
    my $native = $manifest->{native};
    print encode_utf8(join("\n",
        'name=' . text(section($manifest->{package})->{name}),
        'entry=' . text($build->{entry}),
        'sources=' . list($build->{sources}),
        'native=' . (ref $native eq 'HASH' ? 'yes' : 'no'),
        'native.sources=' . list(section($native)->{sources}),
    )), "\n";
    exit 0;
}

if ($mode eq 'includes') {
    for my $file (@ARGV) {
        open(my $in, '<:encoding(UTF-8)', $file) or next;
        while (my $line = <$in>) {
            # A line that is a comment from its start includes nothing. One that only ends in
            # a comment does.
            next if $line =~ /^\s*💭/;
            # Between the two signs the compiler takes any space there is, and the mark that
            # some keyboards put after an emoji, which cannot be seen.
            while ($line =~ /📜(?:\s|\x{FE0F})*🔤(.*?)🔤/g) {
                print $file, ':', $., ':', encode_utf8($1), "\n";
            }
        }
        close($in);
    }
    exit 0;
}

print STDERR "usage: packages.pl manifest <packmoji.json> | includes <source>...\n";
exit 2;
