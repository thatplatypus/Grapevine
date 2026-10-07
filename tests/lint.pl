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
# Types the compiler builds in place, straight into the variable being assigned.
my $inPlace = qr/(?:🍨|🍯)/;

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

    $line =~ /^( *)/;
    my $indent = length($1);
    # What the rules look at is the code alone: text inside string literals and a
    # comment at the end of the line could otherwise hide a match or fake one.
    my $text = substr($line, $indent);
    $text =~ s/🔤.*?🔤/🔤🔤/g;
    $text =~ s/\s*💭.*$//;

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

    # The stock JSON parser's own type is let through here: 🌸 hands it out until the
    # framework has a JSON reader of its own.
    (my $rest = $text) =~ s/🍯🐚⚪(?:\xEF\xB8\x8F)?🍆//g;
    if (!$allow && $rest =~ /🍯🐚|🆕🍯/) {
      print "the standard library's dictionary leaks an entry whenever two keys share a bucket (use 📓, or 🗝 and a list): $where\n";
    }

    my $opens = $text =~ /🍇\s*$/;
    if (!@functions && $opens && ($indent == 2 || ($indent == 0 && $text =~ /^🏁/))) {
      my $header = $text;
      $header =~ s/^(?:🔒|🐇|🥯|🖍|🔓|☣️|✒️|\s)+//;
      my %params = map { $_ => 1 } ($text =~ /\b($name)\b/g);
      push @functions, { indent => $indent, initializer => ($header =~ /^🆕/ ? 1 : 0), closure => 0, locals => {}, params => \%params, pending => '' };
      $kind{$indent} = 'other';
      next;
    }

    my $parent = exists $kind{$indent - 2} ? $kind{$indent - 2} : '';
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
      my $returned = $text =~ /^(?:↩️|🚨) ($name)\s*$/ ? $1 : $text =~ /^↩️ 🔲 ($name) / ? $1 : '';
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
        print "a new 🍨 or 🍯 assigned over a variable leaks the old value (build it in a new variable, then assign that): $where\n";
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
