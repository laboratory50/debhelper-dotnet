# A debhelper build system class for handling .Net (arcade) based projects.
# It prefers out of source tree building.
#
# Copyright: © 2022 Laboratory 50
# License: GPL-3+
#
# This module provides a debhelper buildsystem backend for building .NET projects
# using the dotnet CLI. It automatically detects the installed .NET SDK, overrides
# the TargetFramework property to match the available SDK version, and supports
# selective removal of package/project references via environment variables.
#
# Usage in debian/rules:
#   %:
#       dh $@ --buildsystem=dotnet
#
# Environment variables:
#   NETBUILD_BUILDFILE      - Explicit path to .sln or .csproj file to build
#   NETBUILD_TARGETS        - Space or comma-separated list of project names to build
#   NETBUILD_REMOVE_PACKAGES    - Semicolon-separated list of PackageReference names to remove
#   NETBUILD_REMOVE_REFERENCES  - Semicolon-separated list of ProjectReference paths to remove
#   NETBUILD_REMOVE_IMPORTS     - Semicolon-separated list of Import paths to remove
#   NETBUILD_NO_TFM_OVERRIDE    - If set, disables automatic TargetFramework override

package Debian::Debhelper::Buildsystem::dotnet;

use strict;
use warnings;
use JSON;
use File::Basename;
use File::Find::Rule;
use Data::Dumper;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

# Returns a short description of this buildsystem, displayed by debhelper tools.
sub DESCRIPTION {
    return ".Net build with dotnet CLI";
}

# Indicates whether this buildsystem generates files that should be tracked
# by the build system. Returns 0 (false) as this buildsystem does not generate
# additional build configuration files.
sub IS_GENERATOR_BUILD_SYSTEM {
    return 0;
}

# -----------------------------------------------------------------------------
# SDK detection and information
# -----------------------------------------------------------------------------

# Detects the installed .NET SDK and returns structured information about it.
#
# Searches for the SDK in standard Debian installation paths:
#   - /usr/lib/dotnet
#   - /usr/share/dotnet
#   - /usr/lib/mono
#
# Returns: hashref with keys:
#   - root:    Base installation directory (for DOTNET_ROOT environment variable)
#   - version: Full SDK version string (e.g., "8.0.100")
#   - tfm:     Target Framework Moniker derived from version (e.g., "net8.0")
#
# Dies with error() if no SDK is found.
sub get_sdk_info {
    my @candidates = (
        "/usr/lib/dotnet",
        "/usr/share/dotnet",
        "/usr/lib/mono",
    );

    foreach my $root (@candidates) {
        # Check if the sdk subdirectory exists under this candidate root
        next unless -d "$root/sdk";

        # Find installed SDK versions using File::Find::Rule.
        # We look for directories matching the semantic version pattern X.Y.Z
        # at depth 1 under the sdk directory.
        my @sdk = File::Find::Rule->new()
            ->directory()
            ->maxdepth(1)
            ->name(qr/^\d+\.\d+\.\d+$/)    # Match versions like "8.0.100"
            ->in("$root/sdk");

        next unless @sdk;    # No versions found in this location

        # Extract version string from the first found SDK directory
        my $version = basename($sdk[0]);

        # Derive Target Framework Moniker (TFM) from SDK version.
        # Example: "8.0.100" -> "net8.0"
        # This TFM is used to override the project's TargetFramework property.
        my ($major, $minor) = $version =~ /^(\d+)\.(\d+)/;
        my $tfm = (defined $major && defined $minor)
            ? "net$major.$minor"
            : undef;

        verbose_print("found .Net SDK version $version at $root" .
            (defined $tfm ? " (TFM: $tfm)" : ""));

        return {
            root    => $root,
            version => $version,
            tfm     => $tfm,
        };
    }

    # No SDK found in any of the candidate locations
    error(".Net SDK not found");
}

# -----------------------------------------------------------------------------
# Build system interface methods
# -----------------------------------------------------------------------------

# Determines whether this buildsystem can handle the current source tree.
# Called by debhelper to auto-detect the appropriate buildsystem.
#
# Returns: 1 if buildable, 0 otherwise
sub check_auto_buildable {
    my $this = shift;
    my ($step) = @_;

    # If NETBUILD_BUILDFILE is set, check for that specific file
    if ($ENV{'NETBUILD_BUILDFILE'}) {
        return (-e $this->get_sourcepath($ENV{'NETBUILD_BUILDFILE'})) ? 1 : 0;
    }

    # Otherwise, check for standard .NET project files:
    # - .sln (Visual Studio solution)
    # - .csproj (C# project file)
    # Note: Original code had typo "*.cproj" which has been corrected to "*.csproj"
    return (-e $this->get_sourcepath('*.sln') || -e $this->get_sourcepath('*.csproj')) ? 1 : 0;
}

# Constructor: initializes the buildsystem instance.
#
# Handles environment variables:
#   NETBUILD_BUILDFILE  - Use explicit build file instead of auto-detection
#   NETBUILD_TARGETS    - Build only specified projects from a solution file
sub new {
    my $class = shift;
    my $this  = $class->SUPER::new(@_);
    my %projects;

    # Prefer building in a separate directory (out-of-source build)
    $this->prefer_out_of_source_building(@_);

    # Handle explicit build file specification via NETBUILD_BUILDFILE
    if ($ENV{'NETBUILD_BUILDFILE'}) {
        my $buildfile = $ENV{'NETBUILD_BUILDFILE'};
        if (-e $this->get_sourcepath($buildfile)) {
            $this->{buildfiles} = ($buildfile);
        }
        else {
            error("$buildfile not found");
        }
    }

    # Handle selective project building from solution files via NETBUILD_TARGETS
    if ($ENV{'NETBUILD_TARGETS'}) {
        my @solutions = glob($this->get_sourcepath('*.sln'));

        # Currently, only single-solution builds are supported
        if (@solutions > 1) {
            error("Multiple .sln files found; only single solution builds are supported");
        }
        elsif (@solutions > 0) {
            # Parse solution file to extract project mappings
            %projects = get_sln_projects($solutions[0]);

            # Parse target list: supports both space and comma separators
            my @targets = split /\s+/, $ENV{'NETBUILD_TARGETS'} =~ s/,/ /gr;

            # Add matching projects to the build list
            foreach my $target (@targets) {
                if (exists $projects{$target}) {
                    push @{$this->{buildfiles}}, $projects{$target};
                }
            }
        }
    }

    return $this;
}

# Configure step: executed before building.
# Performs dependency restoration and applies .csproj patches if configured.
sub configure {
    my $this = shift;

    # Apply .csproj patches before restore to ensure correct dependencies
    $this->patch_csproj_files();

    # Restore NuGet packages for all configured build files
    foreach my $command ($this->msbuild_commands('restore', @_)) {
        $this->doit_in_sourcedir(@$command);
    }
}

# Clean step: removes build artifacts.
sub clean {
    my $this = shift;

    # Run dotnet clean for all build files
    foreach my $command ($this->msbuild_commands('clean', @_)) {
        $this->doit_in_sourcedir(@$command);
    }

    # Remove intermediate (obj/) and output (bin/) directories
    if ($this->{buildfiles}) {
        foreach my $buildfile (@{$this->{buildfiles}}) {
            $this->doit_in_sourcedir('rm', '-rf', get_intermediate_outputpath($buildfile));
            $this->doit_in_sourcedir('rm', '-rf', get_outputpath($buildfile));
        }
    }
}

# Build step: compiles the project(s).
sub build {
    my $this = shift;
    foreach my $command ($this->msbuild_commands('build', @_)) {
        $this->doit_in_sourcedir(@$command);
    }
}

# Test step: runs project tests.
sub test {
    my $this = shift;
    foreach my $command ($this->msbuild_commands('test', @_)) {
        $this->doit_in_sourcedir(@$command);
    }
}

# -----------------------------------------------------------------------------
# Command generation
# -----------------------------------------------------------------------------

# Generates a list of commands for the given build step.
# Handles both single-file and multi-file build configurations.
sub msbuild_commands {
    my $this  = shift;
    my @result;

    if ($this->{buildfiles}) {
        # Generate command for each explicitly configured build file
        foreach my $buildfile (@{$this->{buildfiles}}) {
            push @result, $this->msbuild_command($buildfile, @_);
        }
    }
    else {
        # Generate command for auto-detected project(s)
        push @result, $this->msbuild_command(undef, @_);
    }

    return @result;
}

# Constructs a single dotnet command with appropriate options and environment.
#
# Key features:
#   - Sets DOTNET_ROOT to use the detected SDK installation
#   - Disables multi-level lookup for deterministic builds
#   - Overrides TargetFramework to match the available SDK version
#   - Adds Release configuration for build/test steps
#   - Supports custom MSBuild targets via $this->{targets}
#
# Returns: arrayref representing the command to execute
sub msbuild_command {
    my $this      = shift;
    my $buildfile = shift;
    my $step      = shift;
    my @options   = @_;

    # Log the operation for verbose output
    print("\t$step " . ($buildfile // '(solution)') . "\n");

    # Add build file path if specified
    push @options, $buildfile if $buildfile;

    # Use Release configuration for build and test steps
    if ($step eq 'build' or $step eq 'test') {
        push @options, '-c', 'Release';
    }

    # Add custom MSBuild targets if configured
    if ($this->{targets}) {
        foreach my $target (split ' ', $this->{targets}) {
            push @options, "-t:$target";
        }
    }

    # Get SDK information for environment configuration
    my $sdk_info = get_sdk_info();

    # Override TargetFramework to match the detected SDK version.
    # This allows building projects targeting older frameworks with newer SDKs.
    # Can be disabled by setting NETBUILD_NO_TFM_OVERRIDE environment variable.
    if (defined $sdk_info->{tfm} && !$ENV{NETBUILD_NO_TFM_OVERRIDE}) {
        push @options, "-p:TargetFramework=$sdk_info->{tfm}";
        verbose_print("overriding TargetFramework to $sdk_info->{tfm}");
    }

    # Construct the final command with environment variables:
    #   DOTNET_ROOT              - Points to the detected SDK installation
    #   DOTNET_MULTILEVEL_LOOKUP - Disabled to ensure deterministic SDK selection
    my @cmd = (
        "env",
        "DOTNET_ROOT=$sdk_info->{root}",
        "DOTNET_MULTILEVEL_LOOKUP=0",
        "dotnet", $step, @options
    );

    return \@cmd;
}

# -----------------------------------------------------------------------------
# .csproj patching support
# -----------------------------------------------------------------------------

# Applies patches to .csproj files to remove unwanted references.
#
# Controlled by environment variables:
#   NETBUILD_REMOVE_PACKAGES    - Remove PackageReference elements
#   NETBUILD_REMOVE_REFERENCES  - Remove ProjectReference elements
#   NETBUILD_REMOVE_IMPORTS     - Remove Import elements
#
# Original files are automatically restored during the clean step via
# restore_file_on_clean() from Debian::Debhelper::Dh_Lib.
sub patch_csproj_files {
    my $this = shift;

    # Read configuration from environment variables
    my $remove_packages   = $ENV{NETBUILD_REMOVE_PACKAGES}   || '';
    my $remove_references = $ENV{NETBUILD_REMOVE_REFERENCES} || '';
    my $remove_imports    = $ENV{NETBUILD_REMOVE_IMPORTS}    || '';

    # Exit early if no patches are configured
    return unless $remove_packages || $remove_references || $remove_imports;

    # Determine which .csproj files to process
    my @csproj_files;
    if ($this->{buildfiles}) {
        @csproj_files = grep { /\.csproj$/ } @{$this->{buildfiles}};
    }
    else {
        @csproj_files = glob($this->get_sourcepath('*.csproj'));
    }

    return unless @csproj_files;

    verbose_print("patching " . scalar(@csproj_files) . " .csproj file(s)");

    foreach my $csproj (@csproj_files) {
        my $filepath = $this->get_sourcepath($csproj);
        next unless -e $filepath;

        # Register file for automatic restoration during clean
        restore_file_on_clean($filepath);

        # Read file content with UTF-8 encoding support
        open my $fh, '<:encoding(UTF-8)', $filepath or error("Cannot read $filepath: $!");
        my $content = do { local $/; <$fh> };
        close $fh;

        my $modified = 0;

        # Remove PackageReference elements matching configured names
        if ($remove_packages) {
            my @packages = split /\s*[;,]\s*/, $remove_packages;
            foreach my $pkg (@packages) {
                $pkg =~ s/^\s+|\s+$//g;
                next unless $pkg;

                # Match both self-closing and multi-line PackageReference elements
                # Pattern: <PackageReference Include="PackageName" ... />
                my $count = ($content =~ s/<PackageReference\s+Include=["']\Q$pkg\E["'][^>]*\/>//g);
                $count += ($content =~ s/<PackageReference\s+Include=["']\Q$pkg\E["'][^>]*>.*?<\/PackageReference>//gs);

                if ($count > 0) {
                    verbose_print("removed PackageReference '$pkg' from $csproj ($count occurrence(s))");
                    $modified = 1;
                }
            }
        }

        # Remove ProjectReference elements matching configured paths
        if ($remove_references) {
            my @refs = split /\s*[;,]\s*/, $remove_references;
            foreach my $ref (@refs) {
                $ref =~ s/^\s+|\s+$//g;
                next unless $ref;

                my $count = ($content =~ s/<ProjectReference\s+Include=["']\Q$ref\E["'][^>]*\/>//g);
                $count += ($content =~ s/<ProjectReference\s+Include=["']\Q$ref\E["'][^>]*>.*?<\/ProjectReference>//gs);

                if ($count > 0) {
                    verbose_print("removed ProjectReference '$ref' from $csproj ($count occurrence(s))");
                    $modified = 1;
                }
            }
        }

        # Remove Import elements matching configured paths
        if ($remove_imports) {
            my @imports = split /\s*[;,]\s*/, $remove_imports;
            foreach my $imp (@imports) {
                $imp =~ s/^\s+|\s+$//g;
                next unless $imp;

                # Match Import with optional Project= attribute
                my $count = ($content =~ s/<Import\s+(?:Project=)?["']\Q$imp\E["'][^>]*\/>//g);
                $count += ($content =~ s/<Import\s+(?:Project=)?["']\Q$imp\E["'][^>]*>.*?<\/Import>//gs);

                if ($count > 0) {
                    verbose_print("removed Import '$imp' from $csproj ($count occurrence(s))");
                    $modified = 1;
                }
            }
        }

        # Write modified content back to file if changes were made
        if ($modified) {
            open my $out, '>:encoding(UTF-8)', $filepath or error("Cannot write $filepath: $!");
            print $out $content;
            close $out;
            verbose_print("updated $csproj");
        }
    }
}

# -----------------------------------------------------------------------------
# Solution file parsing
# -----------------------------------------------------------------------------

# Parses a Visual Studio solution (.sln) file and extracts project mappings.
#
# Returns: hash mapping project names to relative paths (with normalized slashes)
sub get_sln_projects {
    my ($slnfile) = shift;
    my %projects;

    open my $fh, '<', $slnfile or error("Cannot open $slnfile: $!");

    while (my $line = <$fh>) {
        # Parse Project entries: Project("{GUID}") = "Name", "Path", "{GUID}"
        if ($line =~ /^Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)"/) {
            my ($name, $path) = ($1, $2);
            # Normalize Windows-style backslashes to Unix forward slashes
            $projects{$name} = $path =~ s/\\/\//gr;
        }
    }

    close $fh;
    return %projects;
}

# -----------------------------------------------------------------------------
# Path helpers
# -----------------------------------------------------------------------------

# Returns the intermediate output directory for a given build file.
# Convention: same directory as project file, subdirectory "obj"
sub get_intermediate_outputpath {
    return dirname(shift) . '/obj';
}

# Returns the final output directory for a given build file.
# Convention: same directory as project file, subdirectory "bin"
sub get_outputpath {
    return dirname(shift) . '/bin';
}

1;
