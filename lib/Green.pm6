unit module Green;

my @sets;
my ($p0, $i,$i2) = 1, 0, 0;
my Channel $CHANNEL .=new;
my ($pass,$fail)  = '[P]', '[F]';
my $space         = 3;
my $tests         = 0;
my $passing       = 0;
my $t0            = now;
my $supply        = Supply.new;
my $tsets         = 0;
my $csets         = 0;
my $completion    = Promise.new;
my $t1;

my @promises;
my %results;


my @prefixed;

multi sub prefix:<\>\>>(| (Bool $bool, Str $descr? = "Prefixed {$p0}")) is export(:DEFAULT, :harness) is hidden-from-backtrace {
  $p0++;
  @prefixed.push($%(
    test => "$descr",
    sub  => sub :: is hidden-from-backtrace { die 'not ok' unless $bool; },
  ));
};

multi sub prefix:<\>\>>(Callable $sub, Str $descr? = "Prefixed {$p0}") is export(:DEFAULT, :harness) is hidden-from-backtrace { 
  $p0++;
  @prefixed.push($%(
    test => $descr, 
    sub  => $sub,
  ));
};

multi sub set(Callable $sub) is export(:DEFAULT, :harness) is hidden-from-backtrace { set("Suite $i", $sub); }

multi sub set(Str $description, Callable $sub) is export(:DEFAULT, :harness) is hidden-from-backtrace {
  my $test = 0;
  my @tests;
  my multi sub test(Callable $sub) is export(:DEFAULT, :harness) is hidden-from-backtrace { test("Test $i2", $sub); };
  my multi sub test(Str $description, Callable $sub) is export(:DEFAULT, :harness) is hidden-from-backtrace {
    $i2++;
    @tests.push($%(
      test => $description,
      sub  => $sub,
    ));
  };
  $i++;
  $sub();
  $tsets++;
  $CHANNEL.send({
    description => $description,
    tests       => @tests,
  });
}

sub ok (Bool $eval, Str $testname? = '') is export(:harness) is hidden-from-backtrace {
  if $?CALLER::PACKAGE ~~ GLOBAL {
    >> sub :: is hidden-from-backtrace { ok $eval; };
    return;
  }
  die 'not ok' unless $eval;
  return True;
}


$supply.tap(-> $i {
  try print %results{$i};
  $completion.keep(True) if $tsets == ++$csets;
});

start {
  loop {
    my $set = $CHANNEL.receive;
    my ($err, $index) = 1, 1;
    try {
      require Term::ANSIColor;
      my $color = GLOBAL::Term::ANSIColor::EXPORT::DEFAULT::<&color>;
      $pass = $color.('green') ~ '✓' ~ $color.('reset');
      $fail = $color.('red') ~ '✗' ~ $color.('reset');
    };


    my $i = @promises.elems;
    @promises.push(start {
      my Str  $output  = '';
      my Str  $errors  = '';
      my Bool $overall = True;
      my $ti = 1;
      @($set<tests>.list).map({.perl}).join("\n").say;
      for @($set<tests>) -> $test {
        my Bool $success;
        try { 
          $tests++;
          my $promise = Promise.new;
          my $done    = sub :: is hidden-from-backtrace { $promise.keep(True); };
          my $donf = try { 
            ($test<sub>.signature.count == 1 && $test<sub>.signature.params[0].name ne '$_') || ($test<sub>.signature.count > 1);
          } // False;
          await Promise.anyof($promise, start {
            $test<sub>($done)           if  $donf;
            await $promise              if  $donf;
            $promise.keep($test<sub>()) unless $donf;
          });
          $success = $promise.result;
          $passing++ if $success;
          CATCH { 
            default {
              $overall = False;
              $success = False; 
              $errors ~= "{' ' x $space*2}#$err - " ~ $_.Str ~ "\n";
              $errors ~= try $_.backtrace.Str.lines.map({ 
                .subst(/ ^ \s+ /, ' ' x ($space*3)) 
              }).join("\n") ~ "\n"; 
            }
          }
        };
        try $output ~= "{' ' x $space*2}{$success ?? $pass !! $fail ~ " #{$err++} -" } {($test<test> // '').Str.trim}\n"; 
      }
      %results{$i} = "{' ' x $space}{$overall ?? $pass !! $fail} $set<description>\n" ~ $output ~ "\n{$errors}{$errors ne '' ?? "\n" !! ''}";
      $supply.emit($i);
    });
  }
};

END {
  if @prefixed.elems {
    $tsets++;
    $CHANNEL.send({
      description => "Prefixed Tests",
      tests       => @prefixed,      
    });
  }

  await $completion if $tsets != 0;
  $t1 = now;
  say "{' ' x $space}{$passing == $tests ?? $pass !! $fail} $passing of $tests passing ({ sprintf('%.3f', ($t1-$t0)*1000); }ms)" if %results.keys.elems;
  exit 1 if $passing != $tests;
};
