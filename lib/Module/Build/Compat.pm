
package Module::Build::Compat;
$VERSION = '0.02';

use strict;
use File::Spec;
use IO::File;
use Config;

my %makefile_to_build = 
  (
   PREFIX  => 'prefix',
   LIB     => 'lib',
  );

sub create_makefile_pl {
  my ($package, $type, $build) = @_;
  
  die "Don't know how to build Makefile.PL of type '$type'"
    unless $type =~ /^(small|passthrough|traditional)$/;

  my $fh = IO::File->new('> Makefile.PL') or die "Can't write Makefile.PL: $!";

  if ($type eq 'small') {
    print {$fh} <<'EOF';
    use Module::Build::Compat 0.02;
    Module::Build::Compat->run_build_pl(args => \@ARGV);
    Module::Build::Compat->write_makefile();
EOF

  } elsif ($type eq 'passthrough') {
    print {$fh} <<'EOF';

    unless (eval "use Module::Build::Compat 0.02; 1" ) {
      print "This module requires Module::Build to install itself.\n";
      
      require ExtUtils::MakeMaker;
      my $yn = ExtUtils::MakeMaker::prompt
	('  Install Module::Build now from CPAN?', 'y');
      
      unless ($yn =~ /^y/i) {
	warn " *** Cannot install without Module::Build.  Exiting ...\n";
	exit 1;
      }

      require Cwd;
      require File::Spec;
      require CPAN;
      
      # Save this 'cause CPAN will chdir all over the place.
      my $cwd = Cwd::cwd();
      my $makefile = File::Spec->rel2abs($0);
      
      CPAN::Shell->install('Module::Build::Compat');
      
      chdir $cwd or die "Cannot chdir() back to $cwd: $!";
      exec $^X, $makefile, @ARGV;  # Redo now that we have Module::Build
    }
    Module::Build::Compat->run_build_pl(args => \@ARGV);
    Module::Build::Compat->write_makefile();
EOF
    
  } elsif ($type eq 'traditional') {
    my %prereq = ( %{$build->requires}, %{$build->build_requires} );
    delete $prereq{perl};
    my $prereq = join '', map "\t\t\t'$_' => '$prereq{$_}',\n", keys %prereq;

    printf {$fh} <<'EOF', $build->dist_name, $build->dist_version, $prereq;
    use ExtUtils::MakeMaker;
    WriteMakefile
      ('DISTNAME' => '%s',
       'VERSION' => '%s',
       'PL_FILES' => {},
       'PREREQ_PM' => {
%s
		      },
      );
EOF
  }
}


sub makefile_to_build_args {
  shift;
  my @out;
  foreach my $arg (@_) {
    my ($key, $val) = $arg =~ /^(\w+)=(.+)/ or die "Malformed argument '$arg'";
    if (exists $Config{lc($key)}) {
      push @out, lc($key) . "=$val";
    } elsif (exists $makefile_to_build{$key}) {
      push @out, "$makefile_to_build{$key}=$val";
    } else {
      die "Unknown parameter '$key'";
    }
  }
  return @out;
}

sub run_build_pl {
  my ($pack, %in) = @_;
  $in{script} ||= 'Build.PL';
  my @args = $in{args} ? $pack->makefile_to_build_args(@{$in{args}}) : ();
  print "$^X $in{script} @args\n";
  system($^X, $in{script}, @args) == 0 or die "Couldn't run $in{script}: $!";
}

sub fake_makefile {
  my $makefile = $_[1];
  my $build = File::Spec->catfile( '.', 'Build' );

  return <<"EOF";
all :
	$^X $build
realclean :
	$^X $build realclean
	$^X -e unlink -e shift $makefile
.DEFAULT :
	$^X $build \$@
.PHONY   : install manifest
EOF
}

sub fake_prereqs {
  my $file = File::Spec->catfile('_build', 'prereqs');
  my $fh = IO::File->new("< $file") or die "Can't read $file: $!";
  my $prereqs = eval do {local $/; <$fh>};
  close $fh;
  
  my @prereq;
  foreach my $section (qw/build_requires requires recommends/) {
    foreach (keys %{$prereqs->{$section}}) {
      next if $_ eq 'perl';
      push @prereq, "$_=>q[$prereqs->{$section}{$_}]";
    }
  }

  return unless @prereq;
  return "#     PREREQ_PM => { " . join(", ", @prereq) . " }\n\n";
}


sub write_makefile {
  my ($pack, %in) = @_;
  $in{makefile} ||= 'Makefile';
  open  MAKE, "> $in{makefile}" or die "Cannot write $in{makefile}: $!";
  print MAKE $pack->fake_prereqs;
  print MAKE $pack->fake_makefile($in{makefile});
  close MAKE;
}

1;
__END__


=head1 NAME

Module::Build::Compat - Compatibility with ExtUtils::MakeMaker

=head1 SYNOPSIS

 # In a Build.PL :
 use Module::Build;
 my $build = Module::Build->new
   ( module_name => 'Foo::Bar',
     license => 'perl',
     create_makefile_pl => 'passthrough' );
 ...

=head1 DESCRIPTION

Because ExtUtils::MakeMaker has been the standard way to distribute
modules for a long time, many tools (CPAN.pm, or your system
administrator) may expect to find a working Makefile.PL in every
distribution they download from CPAN.  If you want to throw them a
bone, you can use Module::Build::Compat to automatically generate a
Makefile.PL for you, in one of several different styles.

Module::Build::Compat also provides some code that helps out the
Makefile.PL at runtime.

=head1 METHODS

=over 4

=item create_makefile_pl( $style, $build )

Creates a Makefile.PL in the current directory in one of several
styles, based on the supplied Module::Build object C<$build>.  This is
typically controlled by passing the desired style as the
C<create_makefile_pl> parameter to Module::Build's C<new()> method;
the Makefile.PL will then be automatically created during the
C<distdir> action.

The currently supported styles are:

=over 4

=item small

A small Makefile.PL will be created that passes all functionality
through to the Build.PL script in the same directory.  The user must
already have Module::Build installed in order to use this, or else
they'll get a module-not-found error.

=item passthrough

This is just like the C<small> option above, but if Module::Build is
not already installed on the user's system, the script will offer to
use C<CPAN.pm> to download it and install it before continuing with
the build.

=item traditional

A Makefile.PL will be created in the "traditional" style, i.e. it will
use C<ExtUtils::MakeMaker> and won't rely on C<Module::Build> at all.
In order to create the Makefile.PL, we'll include the C<requires> and
C<build_requires> dependencies as the C<PREREQ_PM> parameter.

You don't want to use this style if during the C<perl Build.PL> stage
you ask the user questions, or do some auto-sensing about the user's
environment, or if you subclass Module::Build to do some
customization, because the vanilla Makefile.PL won't do any of that.

=back

=item run_build_pl( args => \@ARGV )

This method runs the Build.PL script, passing it any arguments the
user may have supplied to the C<perl Makefile.PL> command.  Because
ExtUtils::MakeMaker and Module::Build accept different arguments, this
method also performs some translation between the two.

C<run_build_pl()> accepts the following named parameters:

=over 4

=item args

The C<args> parameter specifies the parameters that would usually
appear on the command line of the C<perl Makefile.PL> command -
typically you'll just pass a reference to C<@ARGV>.

=item script

This is the filename of the script to run - it defaults to C<Build.PL>.

=back


=item write_makefile()

This method writes a 'dummy' Makefile that will pass all commands
through to the corresponding Module::Build actions.

C<write_makefile()> accepts the following named parameters:

=over 4

=item makefile

The name of the file to write - defaults to the string C<Makefile>.

=back

=back

=head1 SCENARIOS

So, some common scenarios are:

=over 4

=item 1.

Just include a Build.PL script (without a Makefile.PL
script), and give installation directions in a README or INSTALL
document explaining how to install the module.  In particular, explain
that the user must install Module::Build before installing your
module.  I prefer this method, mainly because I believe that the woes
and hardships of doing this are far less significant than most people
would have you believe.  It's also the simplest method, which is nice.
But anyone with an older version of CPAN or CPANPLUS on their system
will probably have problems installing your module with it.

=item 2.

Include a Build.PL script and a "traditional" Makefile.PL,
created either manually or with create_makefile_pl().  Users won't
ever have to install Module::Build, but in truth it's difficult to
create a proper Makefile.PL

=item 3.

Include a Build.PL script and a "pass-through" Makefile.PL
built using Module::Build::Compat.  This will mean that people can
continue to use the "old" installation commands, and they may never
notice that it's actually doing something else behind the scenes.

=back

=head1 AUTHOR

Ken Williams, ken@mathforum.org

=head1 SEE ALSO

Module::Build(3), ExtUtils::MakeMaker(3)

=cut
