package Debian::Debhelper::Buildsystem::dotnet;

use strict;
use warnings;
use File::Basename;
use File::Find::Rule qw/ find /;
use Debian::Debhelper::Dh_Lib qw/ error verbose_print /;
use parent qw/ Debian::Debhelper::Buildsystem /;

sub DESCRIPTION { ".Net build with MSBuild" }
sub IS_GENERATOR_BUILD_SYSTEM { 0 }

sub sdk_to_tfm {
        my ($ver) = @_;
        return $ver =~ /^(\d+\.\d+)/ ? "net$1" : "net8.0";
}

sub get_projects {
        my ($self) = @_;
        return @{$self->{buildfiles}} if $self->{buildfiles} && @{$self->{buildfiles}};
        return find(file => name => qr/\.csproj$/, maxdepth => 5)->in($self->get_sourcedir());
}

sub get_bin_dir {
        my ($self, $proj) = @_;
        return dirname($proj) . "/bin/Release/" . $self->{target_framework};
}

sub get_obj_dir {
        my ($self, $proj) = @_;
        return dirname($proj) . '/obj';
}

sub ensure_dir {
        my ($path) = @_;
        mkdir($path, 0755) unless -d $path;
}

sub get_sdk_version {
        my ($self) = @_;
        return $self->{sdk_version} if $self->{sdk_version};

        my $ver = `dotnet --version 2>&1`;
        chomp $ver;

        if ($ver =~ /^(\d+\.\d+\.\d+)/) {
                $self->{sdk_version} = $1;
                verbose_print("Found .NET SDK: $self->{sdk_version}");
                return $self->{sdk_version};
        }

        error($ver =~ /not found/i ? ".NET SDK not found" : "Failed to parse SDK version: $ver");
}

sub new {
        my ($class, @args) = @_;
        my $self = $class->SUPER::new(@args);
        $self->prefer_out_of_source_building(@args);

        eval {
                my $sdk = $self->get_sdk_version();
                $self->{target_framework} = sdk_to_tfm($sdk);
                verbose_print("Using TargetFramework: $self->{target_framework}");
        };
        $self->{target_framework} = "net8.0" if $@;

        my $deb_ver = `dpkg-parsechangelog --show-field Version 2>/dev/null`;
        chomp $deb_ver;
        $self->{debian_version} = ($deb_ver =~ /^[\d.+\-~]+/) ? $deb_ver : "1.0.0";
        verbose_print("Debian version: $self->{debian_version}");

        $self->{pack_enabled} = ($ENV{NETBUILD_PACK_ENABLED} eq '0') ? 0 : 1;
        $self->{pack_output}  = $ENV{NETBUILD_PACK_OUTPUT} || 'artifact/packages';

        verbose_print("Pack: output=$self->{pack_output}") if $self->{pack_enabled};

        $self->init_build_targets;

        return $self;
}

sub init_build_targets {
        my ($self) = @_;

        if ($ENV{NETBUILD_BUILDFILE}) {
                my $f = $ENV{NETBUILD_BUILDFILE};
                error("$f not found") unless -e $self->get_sourcepath($f);
                $self->{buildfiles} = [$f];
                verbose_print("Build file: $f");
                return;
        }

        return unless $ENV{NETBUILD_TARGETS};

        my @targets = grep { length } split /[\s,]+/, $ENV{NETBUILD_TARGETS};
        my @files;
        my %sln = $self->parse_solution if -e $self->get_sourcepath('*.sln');

        for my $t (@targets) {
                my $path;
                $path = $self->get_sourcepath($t) if -e $self->get_sourcepath($t);
                $path = $self->get_sourcepath($sln{$t}) if !$path && $sln{$t};
                $path = $self->find_project_by_name($t) if !$path;

                if ($path) {
                        push @files, $path;
                        verbose_print("Target '$t': $path");
                }
                else {
                        verbose_print("Warning: Project '$t' not found");
                }
        }

        $self->{buildfiles} = \@files if @files;
        verbose_print("Projects to build: " . join(', ', @files)) if @files;
}

sub parse_solution {
        my ($self) = @_;
        my ($sln) = glob($self->get_sourcepath('*.sln'));
        return () unless $sln;

        verbose_print("Found solution: $sln");
        my %projects;

        open my $fh, '<', $sln or return ();
        while (<$fh>) {
                if (/^Project\("[^"]+"\)\s*=\s*"([^"]+)",\s*"([^"]+)"/) {
                        $projects{$1} = $2 =~ s/\\/\//gr;
                }
        }
        close $fh;

        verbose_print("Projects in solution: " . join(', ', keys %projects));
        return %projects;
}

sub find_project_by_name {
        my ($self, $name) = @_;
        for my $p (find(file => name => qr/\.csproj$/, maxdepth => 5)->in($self->get_sourcedir())) {
                return $p if basename($p, '.csproj') eq $name;
        }
        return undef;
}

sub check_auto_buildable {
        my ($self, $step) = @_;
        return -e $self->get_sourcepath($ENV{NETBUILD_BUILDFILE}) if $ENV{NETBUILD_BUILDFILE};
        return -e $self->get_sourcepath('*.sln') || -e $self->get_sourcepath('*.csproj');
}

sub configure {
        my ($self) = @_;
        $self->run_msbuild('restore');
}

sub build {
        my ($self) = @_;
        $self->run_msbuild('build');
        $self->pack if $self->{pack_enabled};
}

sub test {
        my ($self) = @_;
        $self->run_msbuild('test');
}

sub clean {
        my ($self) = @_;

        eval { $self->run_msbuild('clean') };
        verbose_print("Warning: dotnet clean failed: $@") if $@;

        for my $proj (get_projects($self)) {
                $self->doit_in_sourcedir('rm', '-rf', get_obj_dir($self, $proj));
                $self->doit_in_sourcedir('rm', '-rf', get_bin_dir($self, $proj));
        }
}

sub run_msbuild {
        my ($self, $step) = @_;

        for my $proj (get_projects($self)) {
                my @cmd = $self->build_cmd($proj, $step);
                verbose_print("Command: @cmd") if $step eq 'build';
                $self->doit_in_sourcedir(@cmd);
        }
}

sub build_cmd {
        my ($self, $proj, $step) = @_;
        my @opts;

        push @opts, $proj if $proj;
        push @opts, '-c', 'Release' if $step =~ /^(build|test)$/;
        push @opts, '-p:TargetFrameworks=' . $self->{target_framework} if $self->{target_framework};

        if ($self->{targets}) {
                push @opts, "-t:$_" for split ' ', $self->{targets};
        }

        return ('dotnet', $step, @opts);
}

sub pack {
        my ($self) = @_;
        verbose_print("Packing projects...");

        my $out = $self->get_sourcepath($self->{pack_output});
        ensure_dir($out);

        for my $proj (get_projects($self)) {
                my @opts = (
                        'pack', $proj, '-c', 'Release',
                        '--no-build', '--no-restore',
                        '-o', $out,
                        '-p:PackageVersion=' . $self->{debian_version},
                        '-p:Version=' . $self->{debian_version}
                );

                push @opts, '-p:TargetFrameworks=' . $self->{target_framework}
                        if $self->{target_framework};

                verbose_print("Pack command: dotnet @opts");
                $self->doit_in_sourcedir('dotnet', @opts);
        }
        verbose_print("Packing completed: $out");
}

1;
