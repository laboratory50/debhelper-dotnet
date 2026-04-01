package Debian::Debhelper::Buildsystem::dotnet;

use strict;
use warnings;
use JSON;
use File::Basename;
use File::Find::Rule qw/ find rule /;
use File::Copy qw/ copy /;
use Data::Dumper;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

sub DESCRIPTION {
        ".Net build with MSBuild"
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

sub sdk_version_to_tfm {
        my ($sdk_version) = @_;
        if ($sdk_version =~ /^(\d+)\.(\d+)/) {
                return "net$1.$2";
        }
        return "net8.0";
}

sub get_sdk_version {
        my $this = shift;
        
        return $this->{sdk_version} if $this->{sdk_version};
        
        my $ver = `dotnet --version 2>&1`;
        chomp($ver);
        
        if ($ver && $ver =~ /^(\d+\.\d+\.\d+)/) {
                my $version = $1;
                verbose_print("found .Net SDK $version via CLI");
                $this->{sdk_version} = $version;
                return $version;
        }
        
        if ($ver =~ /not found|command not found/i) {
                error(".Net SDK not found - please install dotnet-sdk-8.0");
        }
        else {
                error("Failed to parse .NET SDK version: '$ver'");
        }
}

sub find_project_by_name {
        my ($this, $name) = @_;
        my @projects = find(
                file =>
                maxdepth => 5,
                name => qr/\.csproj$/,
        )->in($this->get_sourcedir());

        foreach my $proj (@projects) {
                my $proj_name = basename($proj, '.csproj');
                if ($proj_name eq $name) {
                        return $proj;
                }
        }
        return undef;
}

sub new {
        my $class=shift;
        my $this=$class->SUPER::new(@_);
        my %projects;

        $this->prefer_out_of_source_building(@_);

        # SDK version и TargetFramework
        eval {
                my $sdk_ver = $this->get_sdk_version();
                my $tfm = sdk_version_to_tfm($sdk_ver);
                $this->{target_framework} = $tfm;
                print "🔧 Found .NET SDK version: $sdk_ver\n";
                print "🔧 Will use TargetFramework: $tfm\n";
        };
        if ($@) {
                print "⚠️  Warning: Could not detect SDK version, using net8.0\n";
                $this->{target_framework} = "net8.0";
        }

        # Версия из Debian changelog
        my $debian_version = `dpkg-parsechangelog --show-field Version 2>/dev/null`;
        chomp($debian_version);
        
        if ($debian_version && $debian_version =~ /^[\d\.\+\-~]+/) {
                $this->{debian_version} = $debian_version;
                print "🔧 Detected Debian version: $debian_version\n";
        }
        else {
                $this->{debian_version} = "1.0.0";
                print "⚠️  Warning: Could not detect Debian version, using $this->{debian_version}\n";
        }

        # ========================================================================
        # Настройки упаковки .nupkg (ПО УМОЛЧАНИЮ ВКЛЮЧЕНО)
        # ========================================================================
        $this->{pack_enabled} = ($ENV{'NETBUILD_PACK_ENABLED'} eq '0') ? 0 : 1;
        
        if ($ENV{'NETBUILD_PACK_PROPERTIES'}) {
                $this->{pack_properties} = $ENV{'NETBUILD_PACK_PROPERTIES'};
        }
        elsif ($this->{pack_enabled}) {
                $this->{pack_properties} = "PackageVersion=$this->{debian_version};Version=$this->{debian_version}";
        }
        else {
                $this->{pack_properties} = '';
        }
        
        $this->{pack_output} = $ENV{'NETBUILD_PACK_OUTPUT'} || 'artifact/packages';
        
        if ($this->{pack_enabled}) {
                print "🔧 Packing enabled: output=$this->{pack_output}, props=$this->{pack_properties}\n";
        }

        # ========================================================================
        # Настройки экспорта DLL (ПО УМОЛЧАНИЮ ВКЛЮЧЕНО)
        # ========================================================================
        $this->{dll_export_enabled} = ($ENV{'NETBUILD_DLL_EXPORT_ENABLED'} eq '0') ? 0 : 1;
        $this->{dll_export_output} = $ENV{'NETBUILD_DLL_EXPORT_OUTPUT'} || 'artifact/lib';
        
        if ($this->{dll_export_enabled}) {
                print "🔧 DLL export enabled: output=$this->{dll_export_output}\n";
        }

        # ========================================================================
        # Обработка NETBUILD_BUILDFILE / NETBUILD_TARGETS
        # ========================================================================
        if ($ENV{'NETBUILD_BUILDFILE'}) {
                my $buildfile = $ENV{'NETBUILD_BUILDFILE'};
                if (-e $this->get_sourcepath($buildfile)) {
                        $this->{buildfiles} = ($buildfile);
                        print "🔧 Build file: $buildfile\n";
                }
                else {
                        error("$buildfile not found");
                }
        }
        elsif ($ENV{'NETBUILD_TARGETS'}) {
                my @targets = split /[\s,]+/, $ENV{'NETBUILD_TARGETS'};
                my @buildfiles;

                my @solutions = glob($this->get_sourcepath('*.sln'));
                my %sln_projects;
                if (@solutions == 1) {
                        %sln_projects = get_sln_projects($solutions[0]);
                        print "🔧 Found solution: $solutions[0]\n";
                        print "🔧 Projects in solution: " . join(', ', keys %sln_projects) . "\n";
                }

                foreach my $target (@targets) {
                        $target =~ s/^\s+|\s+$//g;
                        next if $target eq '';

                        my $found_path;

                        if (-e $this->get_sourcepath($target)) {
                                $found_path = $this->get_sourcepath($target);
                                print "🔧 Target '$target': direct path\n";
                        }
                        elsif (%sln_projects && exists $sln_projects{$target}) {
                                $found_path = $this->get_sourcepath($sln_projects{$target});
                                print "🔧 Target '$target': from solution\n";
                        }
                        else {
                                my $searched = $this->find_project_by_name($target);
                                if ($searched) {
                                        $found_path = $searched;
                                        print "🔧 Target '$target': found by search\n";
                                }
                        }

                        if ($found_path) {
                                push @buildfiles, $found_path;
                        }
                        else {
                                print "⚠️  Warning: Project '$target' not found, skipping\n";
                        }
                }

                if (@buildfiles > 0) {
                        $this->{buildfiles} = \@buildfiles;
                        print "🔧 Projects to build: " . join(', ', @buildfiles) . "\n";
                }
                else {
                        print "⚠️  Warning: No valid projects found, will build all\n";
                }
        }

        return $this;
}

sub check_auto_buildable {
        my $this=shift;
        my ($step)=@_;

        if ($ENV{'NETBUILD_BUILDFILE'}) {
                return (-e $this->get_sourcepath($ENV{'NETBUILD_BUILDFILE'})) ? 1 : 0;
        }
        else {
                return (-e $this->get_sourcepath('*.sln') || -e $this->get_sourcepath('*.csproj')) ? 1 : 0;
        }
}

sub configure {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('restore', @_)) {
                $this->doit_in_sourcedir(@$command);
        }
}

sub build {
        my $this=shift;
        
        # Сборка
        foreach my $command ($this->msbuild_commands('build', @_)) {
                $this->doit_in_sourcedir(@$command);
        }
        
        # Экспорт DLL (если включено)
        if ($this->{dll_export_enabled}) {
                $this->export_dlls(@_);
        }
        
        # Упаковка в .nupkg (если включено)
        if ($this->{pack_enabled}) {
                $this->pack(@_);
        }
}

sub export_dlls {
        my $this = shift;
        
        print "🔧 Exporting DLL files...\n";
        
        my @buildfiles = $this->{buildfiles} ? @{$this->{buildfiles}} : ();
        
        if (!@buildfiles) {
                @buildfiles = find(file => name => qr/\.csproj$/, maxdepth => 5)
                        ->in($this->get_sourcedir());
        }
        
        foreach my $buildfile (@buildfiles) {
                my $bin_dir = dirname($buildfile) . "/bin/Release/" . $this->{target_framework};
                my $output_dir = $this->get_sourcepath($this->{dll_export_output});
                
                if (!-d $bin_dir) {
                        verbose_print("Warning: Build output not found: $bin_dir");
                        next;
                }
                
                if (!-d $output_dir) {
                        mkdir($output_dir, 0755) or verbose_print("Warning: Could not create $output_dir");
                }
                
                my @dll_files = find(file => name => qr/\.dll$/i, maxdepth => 1)->in($bin_dir);
                my @xml_files = find(file => name => qr/\.xml$/i, maxdepth => 1)->in($bin_dir);
                
                foreach my $dll (@dll_files) {
                        my $dest = "$output_dir/" . basename($dll);
                        copy($dll, $dest) or verbose_print("Warning: Could not copy $dll");
                        print "   📦 Copied: " . basename($dll) . "\n";
                }
                
                foreach my $xml (@xml_files) {
                        my $dest = "$output_dir/" . basename($xml);
                        copy($xml, $dest) or verbose_print("Warning: Could not copy $xml");
                        print "   📦 Copied: " . basename($xml) . "\n";
                }
                
                print "🔧 Exported " . scalar(@dll_files) . " DLLs to $output_dir\n";
        }
}

sub pack {
        my $this = shift;
        
        print "🔧 Packing projects...\n";
        
        my @buildfiles = $this->{buildfiles} ? @{$this->{buildfiles}} : ();
        
        if (!@buildfiles) {
                @buildfiles = find(file => name => qr/\.csproj$/, maxdepth => 5)
                        ->in($this->get_sourcedir());
        }
        
        foreach my $buildfile (@buildfiles) {
                my @options = ('pack', $buildfile, '-c', 'Release', '--no-build', '--no-restore');
                
                if ($this->{target_framework}) {
                        push @options, '-p:TargetFrameworks=' . $this->{target_framework};
                }
                
                if ($this->{pack_properties}) {
                        foreach my $prop (split /;/, $this->{pack_properties}) {
                                push @options, "-p:$prop";
                        }
                }
                
                my $output_dir = $this->get_sourcepath($this->{pack_output});
                push @options, '-o', $output_dir;
                
                if (!-d $output_dir) {
                        mkdir($output_dir) or verbose_print("Warning: Could not create $output_dir");
                }
                
                print "🔧 Pack command: " . join(' ', ('dotnet', @options)) . "\n";
                $this->doit_in_sourcedir('dotnet', @options);
        }
}

sub test {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('test', @_)) {
                $this->doit_in_sourcedir(@$command);
        }
}

sub clean {
        my $this=shift;
        
        eval {
                foreach my $command ($this->msbuild_commands('clean', @_)) {
                        $this->doit_in_sourcedir(@$command);
                }
        };
        if ($@) {
                verbose_print("Warning: dotnet clean failed: $@");
        }

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        $this->doit_in_sourcedir('rm', '-rf', get_intermediate_outputpath($buildfile));
                        $this->doit_in_sourcedir('rm', '-rf', get_outputpath($buildfile));
                }
        }
        else {
                my @projects = find(file => name => qr/\.csproj$/, maxdepth => 5)
                        ->in($this->get_sourcedir());
                foreach my $proj (@projects) {
                        $this->doit_in_sourcedir('rm', '-rf', get_intermediate_outputpath($proj));
                        $this->doit_in_sourcedir('rm', '-rf', get_outputpath($proj));
                }
        }
}

sub msbuild_commands {
        my $this = shift;
        my @result;

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        push @result, $this->msbuild_command($buildfile, @_);
                }
        }
        else {
                push @result, $this->msbuild_command(undef, @_);
        }

        return @result;
}

sub msbuild_command {
        my $this = shift;
        my $buildfile = shift;
        my $step = shift;
        my @options = @_;

        if ($buildfile) {
                push @options, $buildfile;
        }

        if ($step eq 'build' or $step eq 'test') {
                push @options, '-c', 'Release';
        }

        if ($this->{target_framework}) {
                push @options, '-p:TargetFrameworks=' . $this->{target_framework};
        }

        if ($this->{targets}) {
                foreach my $target (split ' ', $this->{targets}) {
                        push @options, "-t:$target";
                }
        }

        my @cmd = ('dotnet', $step, @options);
        
        if ($step eq 'build') {
                print "🔧 Build command: " . join(' ', @cmd) . "\n";
        }
        
        return \@cmd;
}

sub get_sln_projects {
        my ($slnfile) = shift;
        my %projects;

        open my $fh, '<', $slnfile or error("Cannot open $slnfile: $!");

        while (my $line = <$fh>) {
                if ($line =~ /^Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)"/) {
                        my ($name, $path) = ($1, $2);
                        $projects{$name} = $path =~ s/\\/\//gr;
                }
        }

        close $fh;
        return %projects;
}

sub get_intermediate_outputpath {
        return dirname(shift) . '/obj';
}

sub get_outputpath {
        return dirname(shift) . '/bin';
}

1;
