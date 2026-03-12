# A debhelper build system class for handling .Net (arcade) based projects.
# It prefers out of source tree building.
#
# Copyright: © 2022 Laboratory 50
# License: GPL-3+

package Debian::Debhelper::Buildsystem::msbuild;

use strict;
use warnings;
use JSON;
use File::Basename;
use File::Find::Rule qw/ find rule /;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

sub DESCRIPTION {
        ".Net build with MSBuild"
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

sub get_sdk_version {
        my $base;
        my @sdk;
        if (-d "/usr/lib/mono/sdk") {
                $base = "/usr/lib/dotnet/sdk";
        }
        elsif (-d "/usr/lib/dotnet/sdk") {
                $base = "/usr/lib/dotnet/sdk";
        }
        elsif (-d "/usr/share/dotnet/sdk") {
                $base = "/usr/share/dotnet/sdk";
        }
        else {
                error(".Net SDK not found");
        }

        @sdk = find(
          directory =>
            maxdepth => 1,
            name => qr/\d+\.\d+\.\d+/,
        )->in($base);

        error(".Net SDK not found") if (!@sdk);

        verbose_print("found .Net SDK @sdk");
        return basename(shift(@sdk));
}

sub check_auto_buildable {
        my $this=shift;
        my ($step)=@_;

        return (-e $this->get_sourcepath("*.sln") || -e $this->get_sourcepath("*.cproj")) ? 1 : 0;
}

sub new {
        my $class=shift;
        my $this=$class->SUPER::new(@_);
        $this->prefer_out_of_source_building(@_);

        if ($ENV{'NETBUILD_TARGETS'}) {
                $this->{targets} = $ENV{'NETBUILD_TARGETS'} =~ s/,/ /r;
        }

        return $this;
}

sub configure {
        my $this=shift;
        $this->doit_in_sourcedir(@$this->msbuild_args('restore', @_));
}

sub clean {
        my $this=shift;
        foreach my $command ($this->msbuild_args('clean', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub build {
        my $this=shift;
        $this->doit_in_sourcedir($this->msbuild_args('build', @_));
}

sub test {
#        my $this=shift;
#        my @args = qw/--test/;
#        $this->doit_in_sourcedir("eng/common/build.sh", @args, @_);
}

sub msbuild_args {
        my $this = shift;
        my $step = shift;
        my @options = @_;
        my @result;

        my $dir = $this->get_sourcedir();

        push @options, '-c', 'Release';

        if ($this->{targets}) {
                foreach my $target (split ' ', $this->{targets}) {
                        push @options, "-t:$target";
                }
        }

        push @result, ['dotnet', $step, @options];

        return @result;
}

1

