#!/usr/bin/perl
#    otpautoinstall.pl is a quick and dirty installation script to install
#    multiple versions of Erlang/OTP from source on the erlang.org home page.
#    The application will download, configure build and install Erlang/OTP.
#
#    Copyright (C) 2012	Peter Bartha <peitur@gmail.com>
# 
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
use strict;

use Getopt::Long;
use File::Path;
use File::stat;
use Fcntl ':mode';

use Data::Dumper;

use constant OTP_URL => "http://www.erlang.org/download";
use constant OTP_PREFIX => "/opt/otp";
use constant OTP_ENBALE => "smp-support";
use constant OTP_DISABLE => "odbc";
use constant OTP_LATEST_LN => "latest";
use constant OTP_DEFAULT_LN => "default";
use constant INSTALL_LOG => "install_log.txt";

use constant J2SDK_PATH => "/usr/local/java/latest";

my ($help, $debug, $test ) = (undef, undef, undef);

my ($otpsrcpath, $otptargetpath, $otprev ) = ( undef, undef, "R15B" );
my ( $disable, $enable, $default );

my ( $webget, $makedefault, $updatedefault, $preclean, $noinstall );
my ($onlyconfig);

my ( $inconfig );
my $error = undef;

$webget = 1;

GetOptions(     
        'r|rev:s' =>    \$otprev,
        't|target:s' => \$otptargetpath,
        's|source:s' => \$otpsrcpath,
        'd|disable:s'   => \$disable,
        'e|enable:s'    => \$enable,
        'default'				=> \$default,
        'I|noinstall'   => \$noinstall,
        'wget'                  => \$webget,
        'clean'         => \$preclean,
        'h|help'        => \$help,
        'debug'         => \$debug,
        'test'          => \$test
);

#print `/bin/pwd`;

if( $help ){
        print_help();
        exit;
}

if( ! defined $otpsrcpath ){
        $otpsrcpath = OTP_PREFIX."/src/".$otprev;       
}

if( ! defined $otptargetpath ) {
        $otptargetpath = OTP_PREFIX."/".$otprev;
}

my $log_fh = open_log( $otpsrcpath."/".INSTALL_LOG );


if( $otptargetpath ){
	if( ! -e $otptargetpath ){
		print $log_fh "Could not find ".$otptargetpath." ... creting now!\n";	
	    create_dir( $otptargetpath ) if !$test;
	}
}else{
	die( "No target path ... ".$otptargetpath."\n" );
}

if( $otpsrcpath){
	if( ! -e $otpsrcpath  ){
		print $log_fh "Could not find ".$otpsrcpath." ... creting now!\n";	
		create_dir( $otpsrcpath ) if !$test;
	}
}else{
	die( "No src path ".$otpsrcpath."\n" );
}


if( $webget  ){
        $otpsrcpath = exec_web_collect( $otprev, $otptargetpath, $otpsrcpath );
}

if( -e $otpsrcpath ){
        print  $log_fh "Enterig source path: ".$otpsrcpath."\n"; 
        chdir( $otpsrcpath );   
}else{
        die("No Source path, ".$otpsrcpath."\n");
}


my $flags = "";


my @disablelist = split( ",", $disable.",".OTP_DISABLE ); 
my @enablelist = split( ",", $enable.",".OTP_ENBALE );

if( $preclean ){
        exec_preclean();
}

if( $error ){
	die( $error );
}

my $confres = exec_configure( prefix => $otptargetpath, srcpath => $otpsrcpath, flags => $flags, disable => \@disablelist, enable => \@enablelist );
if( $error ){
	die( $error );
}


if( $confres ){

        my $makeres = exec_make();
		if( $error ){
			die( $error );
		}

        if( $makeres && !$noinstall ){
                exec_make_install();
        }
        
		if( $error ){
			die( $error );
		}
        
        update_links( prefix => $otptargetpath, default => OTP_DEFAULT_LN, latest => OTP_LATEST_LN, clean => $default );
}



print $log_fh "\ndone\n";
print "\ndone\n";


close_log( $log_fh );

exit;

sub print_help{
        print <<_EOF_,
        otpautoinstall.pl       Script to auto-install Erlang/OTP
        
        r|rev                   OTP Revision (Version), see OTP web page, http://www.erlang.org
        t|target                Target prefix, where to put binary [ /opt/otp ]
        s|source                Source location, where to put source [ /opt/otp/src ]
        d|disable               Modules to disable with configure 
        e|enable                Modules to enable with configure
        default									Make this version the default version
        I|noinstall             Compile, but do not run install 
        wget                    Download and install a revision
        clean                   Run 'make clean' before building 
        h|help                  This help        
        debug                   Debug
        test                    Test actions. Used to see what is being executed, without running the commands 
        
_EOF_
} 


##----------------------------------------------------
# update_links( %options )
#
# - %options
# - $ prefix 
# - $ latest
# - $ default
# - $ clean
sub update_links{
        my ( %options ) = @_;
        
		my $latestln = OTP_LATEST_LN;
		if( defined $options{latest} ){
			$latestln = $options{latest} ;
		}
		
		my $defaultln = OTP_DEFAULT_LN;
        if( defined $options{default} ){
        	$defaultln = $options{default} 
        }
				
        if( ! -e $options{prefix} ){
        	print $log_fh "WARN: No prefix path ".$options{prefix}." does not exist!\n";
        	return undef;
        }
        return undef if( !defined $options{prefix} );

        
        my $full_prefix = $options{prefix};
        	
       	my @pathsplit = split( /\//, $full_prefix );
				pop( @pathsplit );
				my $otp_path = join( "/", @pathsplit );
				
				if( -e $otp_path."/".$latestln ){
					if( is_link( $otp_path."/".$latestln ) ){
						print $log_fh "WARN: Existing latest link found, replacing it now ... \n";
						unlink( $otp_path."/".$latestln );
						create_ln( $full_prefix, $otp_path."/".$latestln );
					}else{
						print $log_fh "WARN: Existing latest file or directory found, not a link. Needs manual fixing!\n";
					}					
				}else{
					print $log_fh "INFO: Created link to latest installation ... \n";
					create_ln( $full_prefix, $otp_path."/".$latestln );
				}
				
				if( -e $otp_path."/".$defaultln && defined $options{clean} ){
					if( is_link( $otp_path."/".$defaultln ) ){
						print $log_fh "WARN: Existing default link found, replacing it now ... \n";
						unlink( $otp_path."/".$defaultln );
						create_ln( $full_prefix, $otp_path."/".$defaultln );
					}else{
						print $log_fh "WARN: Existing default file or directory found, not a link. Needs manual fixing!\n";
					}					
				}else{
					print $log_fh "INFO: Created link to latest installation ... \n";
					create_ln( $full_prefix, $otp_path."/".$defaultln );
				}					
				
}


sub exec_web_collect{
        my $rev = shift;
        my $targetprefix = shift;
		my $srcprefix = shift;
		
#       http://www.erlang.org/download/otp_src_R14B02.tar.gz
        return undef if !$rev;
        
        my $filename = "otp_src_".$rev.".tar.gz";
        my $fullurl = OTP_URL."/".$filename;
        my $tmppath = $srcprefix;
        my $installdir = $srcprefix;

		print $log_fh "Getting Erlang/OTP ".$fullurl."\n" if $debug;
        print $log_fh "Enterig download path: ".$tmppath."\n";

        chdir( $tmppath );        
        
        if( ! -e $filename ){
                my $wget_cmd = "/usr/bin/wget \"".$fullurl."\"";
                print $log_fh "Getting package: ".$wget_cmd."\n";
                if( ! $test && ! $error ){
                	open( CMD, "$wget_cmd  2>&1 |" );
                	while( my $line = <CMD> ){                		
                		chomp( $line );
                		
                		if( $debug ){
                			print $log_fh "OTPINSTALLER: ".$line."\n";
                		}
                	}
                }
                
        }else{
                print $log_fh "Package already exists ... using it instead of doanloading new!\n";
        }
        
        print $log_fh "Extracting package: ".$filename." ... \n";       
        my $extract_command = "/bin/tar xvzf ".$filename;
        if( ! $test && ! $error ) {        	
        	open( CMD, "$extract_command  2>&1 |" );
        	while( my $line = <CMD> ){
        		
        		if( $debug ){
                		print $log_fh "OTPINSTALLER: ".$line."\n";
               		}

        	}
        	
        	chdir( $tmppath."/otp_src_".$rev );
        }
        
        return $tmppath."/otp_src_".$rev;
}


sub exec_preclean{
        
        my $cmd = "/usr/bin/make clean";
        
        print $log_fh "Running clean\n";
        print "# ".$cmd."\n" if $debug; 
        if( !$test && ! $error ){
                open( CL, "$cmd  2>&1 |");
                while( my $line = <CL> ){
                        chomp( $line );                    
                        
                        if( $debug ){
                                print $log_fh "OTPINSTALLER: ".$line."\n";
                        }else{
                                print ".";
                        }
                }
        }
        return 1;
}

sub exec_configure{
        my ( %options ) = @_;
        
        my $cmd = "./configure";
        
        $cmd .= " --prefix=".$options{prefix};
        
        if( defined $options{disable} ){
                foreach my $d ( @{$options{disable}} ) {
                        $cmd .= " --disable-".$d if length( $d );
                }
        }
        
        
        if( defined $options{enable} ){
                foreach my $d ( @{$options{enable}} ) {
                        $cmd .= " --enable-".$d  if length( $d );
                }
        }       

        print $log_fh "Running configure\n";
        print $log_fh "# ".$cmd."\n" if $debug;
        
        if( !$test && !$error ){
                open( CL, "$cmd 2>&1 |");
                while( my $line = <CL> ){                	
                        chomp( $line );
                        
                        if( $debug ){
                                print $log_fh "OTPINSTALLER: ".$line."\n";
                        }else{
                                print ".";                      
                        }
                }
        }
        return 1;
}

sub exec_make{

        my $cmd = "/usr/bin/make";
        print $log_fh "Running make\n";
        
        print $log_fh "# ".$cmd."\n" if $debug; 
        if( !$test && ! $error ){
                open( CL, "$cmd  2>&1 |");
                while( my $line = <CL> ){
                        chomp( $line );
                        
                        if( $debug ){
                                print $log_fh "OTPINSTALLER: ".$line."\n";
                        }else{
                                print ".";
                        }
                }
        }
        return 1;
}



sub exec_make_install{
        my $cmd = "/usr/bin/make install";
        
        print $log_fh "Installing...\n";
        print $log_fh "# ".$cmd."\n" if $debug; 
        if( !$test ){
            open( CL, "$cmd  2>&1 |");
            while( my $line = <CL> ){
                chomp( $line );
                        
                if( $debug ){
                	print $log_fh "OTPINSTALLER: ".$line."\n";
                }else{
                    print ".";
                }
            }
        }
        
        return 1;
}


sub is_link{
        my $fname = shift;
        
        if( ! -e $fname ){
                print $log_fh "WARN: ".$fname." can't be found!\n";
                return undef;
        }
        
        my $fss = lstat( $fname );
        my $mode = $fss->mode();
        
        if( S_ISLNK( $mode ) ){
                return 1;
        }
        
        return 0;
}

sub is_dir{
        my $fname = shift;

        if( ! -e $fname ){
                print $log_fh "WARN: ".$fname." can't be found!\n";
                return undef;
        }

        
        my $fss = stat( $fname );
        my $mode = $fss->mode();
        
        if( S_ISDIR( $mode ) ){
                return 1;
        }
        
        return 0;
}



##------------------------------------------------------
# create_ln( $ref, $refln )
# Create link with ln
# 
# $ref                  : Source file
# $refln                : Target file name, same behaviour as /bin/ln
#
# RETURNS
sub create_ln{
        my ( $ref, $refln  ) = @_;
        
        if( !$refln ){          
                my @da = split( "/" , $ref );
                $refln = pop( @da );            
        }
        
        if( ! -e $refln ){
                my $cmd = "/bin/ln -s ".$ref." ".$refln;
                
                print  $log_fh "".$cmd."\n";
                
                my @res = `$cmd  2>&1` if !$test;
                
        }else{
                print $log_fh "# WARN: '".$refln."' already exist!\n";          
        }
        
        return 1;
}

##------------------------------------------------------
# create_dir( $path, $noshell )
# Create link with ln
# 
# $path                 : Source file
# $noshell              : Target file name, same behaviour as /bin/ln
#
# RETURNS
sub create_dir{
        my ( $path, $noshell ) =  @_;
        return undef if( ! $path );
        return 1 if( -e $path );
        
        if( $noshell ){
                
                mkpath( $path )  if !$test;
                
        }else{
                
                my $cmd = '/bin/mkdir -p';
                $cmd .= " ".$path;
        
                print $cmd."\n";        
                my @res = `$cmd  2>&1 ` if !$test;
                if( scalar( grep(/Error/, @res ) ) > 0 ){
                	$error = "ERROR: ".$cmd."\n";
                }   
        }
        
        return 1;       
}


##------------------------------------------------------
# open_log( $logfile )
# Open file for writing
# 
# $filename		File name to use for logging.
#
# RETURNS
sub open_log{
	my ( $logfile ) = shift;
	
	my $fh;

	print "Install log: ".$logfile."\n";	
	open( $fh, ">", $logfile );
	
	return $fh;
}

sub close_log{
	my ( $fh ) = shift;
	
	if( $fh ){
		close( $fh );
	}
	
	return 1;
}
