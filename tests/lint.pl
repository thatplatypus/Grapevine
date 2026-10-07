#!/usr/bin/env perl
# The structural half of tests/lint.sh: rules that need to know which block or which
# function a line is in. It prints one problem per line and exits 0; lint.sh counts them.
#
# Every rule here is a memory-management defect of the Emojicode 1.0 beta 2 compiler,
# read out of its source (Compiler/MemoryFlowAnalysis, Compiler/AST) and then measured.
# The README's gotchas describe each one.
#
#   perl tests/lint.pl file.🍇 ...
use strict;
use warnings;
# No utf8 pragma on purpose: sources and patterns are both handled as raw bytes, which
# matches emoji exactly and needs nothing beyond the perl-base that the image ships.

my $name = qr/[A-Za-z_][A-Za-z0-9_]*/;

# Types the compiler builds in place, straight into the variable being assigned: the
# standard library's list and dictionary, and every value type declared in the files given.
my @builtInPlace = ('🍨', '🍯');
for my $file (@ARGV) {
  open(my $in, '<', $file) or die "cannot read $file: $!";
  while (my $line = <$in>) {
    push @builtInPlace, $1 if $line =~ /^(?:🌍 )?🕊 (\S+)/;
  }
  close($in);
}
my $inPlace = join('|', map { quotemeta } @builtInPlace);
$inPlace = qr/(?:$inPlace)/;

for my $file (@ARGV) {
  open(my $in, '<', $file) or die "cannot read $file: $!";
  my @lines = <$in>;
  close($in);
  chomp(@lines);

  my %kind;        # indent of a block's opening line => else | unsafe | other
  my $inDoc = 0;
  my $allowed = 0;
  # One entry per function being read, innermost last. A closure is a function of its
  # own to the compiler, so it gets an entry of its own here.
  my @functions;   # { indent, initializer, closure, locals => {}, params => {}, pending }

  # What the rules look at is the code alone: text inside string literals and a comment
  # at the end of a line could otherwise hide a match or fake one. A block written on one
  # line is taken apart into the three lines it stands for, so that no rule is dodged by
  # layout.
  my @code;        # [ indent, text, where, allow ]
  for my $index (0 .. $#lines) {
    my $line = $lines[$index];
    my $where = "$file:" . ($index + 1) . ": $line";

    my $marks = () = $line =~ /📗/g;
    if ($marks == 1) { $inDoc = !$inDoc; next; }
    next if $inDoc || $marks > 1;
    next if $line =~ /^\s*$/;
    # One line can be let through by a 💭 lint-allow: comment directly above it that says why.
    if ($line =~ /^\s*💭/) { $allowed = $line =~ /^\s*💭 lint-allow: \S/ ? 1 : 0; next; }
    my $allow = $allowed;
    $allowed = 0;

    # The rules go by indentation: which block a line is in is read off its spaces. A line
    # indented any other way would be passed without having been looked at, so it is refused.
    if ($line =~ /^ *\t/) {
      print "a line indented with a tab cannot be checked (indent with spaces, two for each level): $where\n" unless $allow;
      next;
    }
    $line =~ /^( *)/;
    my $indent = length($1);
    if ($indent % 2) {
      print "a line indented by an odd number of spaces cannot be checked (two for each level): $where\n" unless $allow;
      next;
    }
    my $text = substr($line, $indent);
    $text =~ s/🔤.*?🔤/🔤🔤/g;
    $text =~ s/\s*💭.*$//;
    # Spelt one way, so that no rule has to know the others.
    $text =~ s/^(↩️|🚨)\s+/$1 /;
    $text =~ s/^🆗(?=\S)/🆗 /;
    # An else on the line that closes the block before it stands for two lines.
    if ($text =~ /^🍉\s+(🙅.*)$/) {
      push @code, [$indent, '🍉', $where, $allow];
      $text = $1;
    }
    if ($text =~ /^((?:↪️|🙅|🔁|🔂|☣️|🆗).*?🍇)\s+(\S.*?)\s*🍉\s*$/ && $1 !~ /🍇.*🍇/) {
      my ($opener, $body) = ($1, $2);
      if ($body =~ /🍇(?!🎍)/ && !$allow) {
        print "a block inside a block on one line cannot be checked (put them on lines of their own): $where\n";
      }
      push @code, [$indent, $opener, $where, $allow], [$indent + 2, $body, $where, $allow], [$indent, '🍉', $where, $allow];
    }
    else {
      push @code, [$indent, $text, $where, $allow];
    }
  }

  for my $entry (@code) {
    my ($indent, $text, $where, $allow) = @$entry;

    # A line at this indent ends every block that was opened at it or deeper.
    for my $level (keys %kind) { delete $kind{$level} if $level >= $indent; }

    while (@functions && $indent <= $functions[-1]{indent}) {
      my $ended = pop @functions;
      # A return that was the last statement is the one place a local may be returned.
      if ($ended->{pending} ne '' && !($indent == $ended->{indent} && $text =~ /^🍉/)) {
        print "a local variable is returned or raised before the end of its function (assign it to a result and return that last): $ended->{pending}\n";
      }
    }
    if (@functions && $functions[-1]{pending} ne '') {
      print "a local variable is returned or raised before the end of its function (assign it to a result and return that last): $functions[-1]{pending}\n";
      $functions[-1]{pending} = '';
    }

    if (!$allow && ($text =~ /🍯🐚|🆕🍯/ || $text =~ /🍿(?:(?!🍆).)*➡️(?:(?!🍆).)*🍆/)) {
      print "the standard library's dictionary leaks an entry whenever two keys share a bucket (use 📓, or 🗝 and a list): $where\n";
    }
    # A closure written on one line never becomes a function of its own below, so what it
    # returns is looked at here. On one line it can only return a parameter or something
    # it captured, and neither is its to give away.
    if (!$allow && $text =~ /🍇🎍🥡((?:(?!🍇|🍉).)*?)↩️\s+($name)\s*🍉/) {
      my ($head, $returned) = ($1, $2);
      if (grep { $_ eq $returned } ($head =~ /\b($name)\b/g)) {
        print "a parameter is returned or raised, but the function does not own it and the caller will free it while it is in use (assign it to a variable and return that): $where\n";
      }
      else {
        print "a closure returns or raises a captured variable, which gives away the closure's own reference (assign it to a variable and return that): $where\n";
      }
    }

    my $opens = $text =~ /🍇\s*$/;
    if (!@functions && $opens && $indent > 2 && !$allow) {
      print "a method that does not start at two spaces cannot be checked (two for each level): $where\n";
    }
    if (!@functions && $opens && ($indent == 2 || ($indent == 0 && $text =~ /^🏁/))) {
      my $header = $text;
      $header =~ s/^(?:🔒|🐇|🥯|🖍|🔓|☣️|✒️|\s)+//;
      my %params = map { $_ => 1 } ($text =~ /\b($name)\b/g);
      push @functions, { indent => $indent, initializer => ($header =~ /^🆕/ ? 1 : 0), closure => 0, locals => {}, params => \%params, pending => '' };
      $kind{$indent} = 'other';
      next;
    }

    # A ☣️ block opens no scope of its own, so what is declared in one belongs to the block around it.
    my $around = $indent - 2;
    $around -= 2 while exists $kind{$around} && $kind{$around} eq 'unsafe';
    my $parent = exists $kind{$around} ? $kind{$around} : '';
    my $unsafe = grep { $kind{$_} eq 'unsafe' } keys %kind;
    my $exits = $text =~ /^(?:↩️|🚨)/;
    my $declares = $text =~ /➡️ 🖍🆕/ || $text =~ /➡️ $name\s*$/ || $text =~ /^🖍🆕 /;

    if ($allow) {
      # Still tracked below as a declaration or a block opener; only the checks are skipped.
    }
    elsif ($parent eq 'else' && $declares) {
      print "variable declared in a plain 🙅 block is never released (use 🙅↪️ with the opposite condition): $where\n";
    }
    if (!$allow && $parent eq 'else' && $exits) {
      print "↩️ or 🚨 directly in a plain 🙅 block releases nothing (use 🙅↪️, or leave the block first): $where\n";
    }
    if (!$allow && $unsafe && $exits) {
      print "↩️ or 🚨 inside a ☣️ block releases nothing (hand the value out of the block first): $where\n";
    }
    if (!$allow && $text =~ /🔺/) {
      print "🔺 hides what its call does with its arguments, and objects end up on the stack (handle the error here, with 🆗 value … 🙅‍♀️): $where\n";
    }
    if (!$allow && $text =~ /^🆗 / && $text !~ /^🆗 $name \S/) {
      print "a 🆗 that binds no value hides what its call does with its arguments (bind the value, and make the call return one): $where\n";
    }

    if (@functions) {
      my $function = $functions[-1];
      my $returned = $text =~ /^(?:↩️|🚨) ($name)\s*$/ ? $1 : $text =~ /^↩️ 🔲 ($name) / ? $1 : $text =~ /^↩️ 🍺 ?($name)\s*$/ ? $1 : '';
      if (!$allow && $returned ne '' && $function->{locals}{$returned}) {
        if ($indent == $function->{indent} + 2) { $function->{pending} = $where; }
        else { print "a local variable is returned or raised from inside a block (assign it to a result and return that last; raise a new error): $where\n"; }
      }
      elsif (!$allow && $returned ne '' && $function->{params}{$returned}) {
        print "a parameter is returned or raised, but the function does not own it and the caller will free it while it is in use (assign it to a variable and return that): $where\n";
      }
      elsif (!$allow && $returned ne '' && $function->{closure}) {
        print "a closure returns or raises a captured variable, which gives away the closure's own reference (assign it to a variable and return that): $where\n";
      }
      if (!$allow && !$function->{initializer} && $text =~ /^🆕$inPlace.*➡️ 🖍($name)\s*$/) {
        print "a new 🍨, 🍯 or other value type assigned over a variable leaks the old value (build it in a new variable, then assign that): $where\n";
      }
      $function->{locals}{$1} = 1 while $text =~ /➡️ 🖍🆕($name)/g;
      $function->{locals}{$1} = 1 if $text =~ /➡️ ($name)(?: 🍇)?\s*$/;
      $function->{locals}{$1} = 1 if $text =~ /^🖍🆕 ($name) /;
      $function->{locals}{$1} = 1 if $text =~ /^(?:🔂|🆗) ($name) /;
      $function->{locals}{$1} = 1 if $text =~ /^🙅‍♀️ ($name) 🍇/;

      # A closure's body starts on the next line and ends at a 🍉 at this line's indent.
      if ($text =~ /🍇🎍🥡(.*)$/ && !$opens) {
        my %params = map { $_ => 1 } ($1 =~ /\b($name)\b/g);
        push @functions, { indent => $indent, initializer => 0, closure => 1, locals => {}, params => \%params, pending => '' };
      }
    }

    if ($opens) {
      $kind{$indent} = $text =~ /^🙅 🍇\s*$/ ? 'else' : $text =~ /^☣️ 🍇\s*$/ ? 'unsafe' : 'other';
    }
  }
}
