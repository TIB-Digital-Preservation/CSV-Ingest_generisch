#!/usr/bin/perl
use lib "/home/user/perl5/lib/perl5/";
use strict;
use warnings;
use Text::CSV;
use XML::Writer;
use XML::LibXML;
use DateTime;
use File::Copy::Recursive qw(dircopy);
use File::Copy qw/move/;
use File::Basename;
use File::Find;
use JSON;
use Data::Dumper;
use Cwd;
use utf8;
use Encode;
binmode STDOUT, ":utf8";    # for output
my $version = "1.2";

#print instructions
print "CSV-Ingest_generisch Version: ".$version."\n";
print "Das Skript erstellt eine CSV und die Ordnerstruktur für den Ingest.
Der erstellte Ordner kann über einen Submission Job geingestet werden.
Die Konfiguration wird über Config.json mitgegeben.
Siehe auch README.MD\n";
print "Checksummendatei: nur einfacher Zeilenumbruch (Linux-Style), Trennzeichen zwischen Prüfsumme und Datei ist ein Tab, Schrägstriche werden umgedreht!\n";

#read in folders
my @allFolders = grep { -d } glob("*");
my @filesComplete;
my @csvCreated;
my @createdSIPs;
my %files_md5s;

my $config;
{
  local $/; #Enable 'slurp' mode
  open my $fh, "<", "Config.json";
  $config = <$fh>;
  close $fh;
}
my $configParams = decode_json($config);

my $accessRight = $configParams->{'accessRight'};
my $userDefinedA = $configParams->{'userDefinedA'};
my $userDefinedB = $configParams->{'userDefinedB'};
my $ieEntityType = $configParams->{'ieEntityType'};
my $dctermsLicense = $configParams->{'dctermsLicense'};

my $dcXmlHeadElement = $configParams->{'dcXmlHeadElement'};
my %sourceMD = %{ $configParams->{'sourceMD'}};
my %representations = %{ $configParams->{'representations'}};
my $subfoldersAsLabel = $configParams->{'subfoldersAsLabel'};
my $ieMD = $configParams->{'ieMD'};
my @checksums = @{ $configParams->{'checksums'} }; # "separat","gesammelt","keine"

my @variableHeaders = ('Access Rights Policy ID (IE)','IE User Defined A','IE User Defined B','IE Entity Type',"License (DCTERMS)");
my @variableIEValues = ($accessRight,$userDefinedA,$userDefinedB,$ieEntityType,$dctermsLicense);

#wenn nur eine Datei für Checksums vorliegt einen Hash erstellen
if ($checksums[0] eq "gesammelt"){
  #check if file exists
  my $checksumfile = $checksums[1];
  if (-f $checksumfile){
    my $filehandle;
    open $filehandle,"<",$checksumfile;
    chomp(my @oldmd5s = <$filehandle>);
    close $filehandle;

    #create hash -> checksums are the values
    foreach my $string (@oldmd5s){
      my @temp_key_value = split( " ", $string, 2 );
      $files_md5s{$temp_key_value[1]} = $temp_key_value[0];
    }
  } else {
    print "Prüfsummendatei fehlt";
    exit;
  }
}

#check if necessary files are available
printRep("CSV-Ingest_generisch Version: ".$version);
printRep("\ncheck of complete\n");
print "\n";
foreach my $folder (@allFolders) {
	my $result_checkComplete = checkComplete($folder);
	if ($result_checkComplete==0){
		push (@filesComplete, $folder);
    printRep($folder.": alles in Ordnung\n\n");
	} elsif ($result_checkComplete==1){
			printRep($folder.": ERROR: es fehlen Dateien, die verpflichtend sind\n\n");
	}
}

#for each folder: make csv
printRep("\nmake CSV files\n");
print "\n";
foreach my $folder (@filesComplete) {
	my $result_csvCreation = createCSV($folder);
	if ($result_csvCreation==0){
		push (@csvCreated, $folder);
		printRep($folder.": alles in Ordnung\n");
	} elsif ($result_csvCreation==1){
			printRep($folder.": Fehler bei Erstellung der CSV aufgetreten\n");
	}
}

#for each folder: generate folderstructure
printRep("\ncreate folderstructure for ingest\n");
print "\n";
foreach my $folder (@csvCreated) {
	print $folder." : ";
	my $mkFolders = mkFolders($folder);
	if ($mkFolders==0){
		printRep("SIP successfully created\n");
		push (@createdSIPs, $folder);
	} else {
		printRep("ERROR: ".$folder." no SIP was created\n");
	}
}

#print report
printRep( "\nreport\n");
printRep( "Anzahl vorhandener Ordner:    ".scalar @allFolders."\n");
printRep( "Anzahl erstellter CSV:    ".scalar @csvCreated."\n");
printRep( "Anzahl erstellter SIPs:    ".scalar @createdSIPs."\n");
printRep( "fertig\n");

###############################################################################
#subroutine checks if all necessary files (at least 1 Masterfile, and 1 dc.xml) are available
#returns int 0 when alle files are avaiable
#returns int 1 when one or both files are missing
sub checkComplete{
	#print "sind Master  und dc.xml vorhanden?\n";
	my $foldername = $_[0];
	my $existError = 0;
  my $existWarning = 0;
	my $errormessage = $foldername.": ";

  #check Filenames
	my $path = getcwd;
	$path = $path."/".$foldername;
	my $numAllFiles = 0;
  my @files;
  find( sub{ push @files, $File::Find::name if (-f $File::Find::name)}, $path);
	#foreach files in the directory (recursively)
	foreach my $file (@files) {
    my $nonascii = $file;
    $nonascii = decode('UTF-8',$nonascii);
    $nonascii =~ s/[[:ascii:]]*//g;
    if ($nonascii ne ""){
      #look at each character separate
      my @splitLine = split(//,$nonascii);
      foreach my $char (@splitLine){
        $char = encode('UTF-8', $char);
        #warn if 4 bytes
        if (length($char) > 3) {
          my $hexCode = $char;
          $hexCode =~ s/(.)/sprintf("%x",ord($1))/eg;
          my $message = "\n--Dateiname enthält 4 Byte character, Hex: ".$hexCode." Dateiname: ".$file."\n";
          $existError = 1;
        	$errormessage = $errormessage.$message;
        }
      }
    }
	}

  #Repräsentationen prüfen, anhand der Angabe ob manatory oder optional unterscheiden zw. Warnung und Fehler
  while ((my $representation, my $isMandatory) = each %representations){
    #wenn Ordner vorhanden ist, aber keine Dateien darin, dann liegt ein Fehler vor
    if (-d "$foldername/$representation"){
      my $num_files = countfiles("$foldername/$representation");
      if ($num_files == 0){
        $existError = 1;
        $errormessage = $errormessage."keine Datei im Ordner ".$representation.", ";
      }
    #wenn kein Ordner vorhanden ist, dann prüfen ob verpflichtend
    } else {
      if ($isMandatory eq "mandatory"){
        $existError = 1;
        $errormessage = $errormessage."kein Pflichtordner ".$representation.", ";
      } else {
        $existWarning = 1;
        $errormessage = $errormessage."kein optionaler Ordner ".$representation.", ";
      }
    }
    #check for checksumsfiles
	if (($checksums[0] eq "separat")||($checksums[0] eq "gesammelt")){
		foreach my $file (@files){
		  if ($file =~ m/$foldername\/$representation/ && $file !~ /.*$checksums[1]$/ && -f $file && $file !~ /.*\.fileMD.xml$/){
			if ($checksums[0] eq "gesammelt"){
			  #check if exists for each file otherwise error
			  my $path = getcwd;
			  $file =~ s/$path\///;
			  unless ($files_md5s{$file}){
				$existError = 1;
				$errormessage = $errormessage."Checksum für  ".$file." fehlt, ";
			  }
			} elsif ($checksums[0] eq "separat"){
			  #TODO check if file exists otherwise error
			  my $checksumfile = $file.$checksums[1];
			  unless (-f $checksumfile){
				$existError = 1;
				$errormessage = $errormessage."Checksumfile ".$checksumfile." fehlt, ";
			  }
			}
		  }
		}
	}
  }

	if (-f "$foldername/dc.xml"){
		my $messCharac = checkCharacters("$foldername/dc.xml");
		if ($messCharac ne "ok"){
			$existError = 1;
			$errormessage = $errormessage.$messCharac;
		}
    my $parser = XML::LibXML->new;
    my $xml = eval { $parser->parse_file("$foldername/dc.xml") };
      if ( ! $xml ) {
          printRep("Can't parse $foldername/dc.xml: $@");
          $existError = 1;
          $errormessage = $errormessage."dc.xml nicht wohlgeformt, ";
      }
	} else {
		$existError = 1;
		$errormessage = $errormessage."dc.xml fehlt, ";
	}

  #if collection.xml file
  if (-f "$foldername/collection.xml"){
	   my $messCharac = checkCharacters("$foldername/collection.xml");
	   if ($messCharac ne "ok"){
		      $existError = 1;
		      $errormessage = $errormessage.$messCharac;
	   }
     if (-z "$foldername/collection.xml"){
       $existError = 1;
       $errormessage = $errormessage."collection.xml ist eine leere Datei, ";
     }
     printRep($foldername.": collection.xml vorhanden\n");
  }

  #check if ieMD exist
  if ($ieMD eq "true") {
    if (-f "$foldername/ieMD.xml"){
		my $messCharac = checkCharacters("$foldername/ieMD.xml");
		if ($messCharac ne "ok"){
			$existError = 1;
			$errormessage = $errormessage.$messCharac;
		}
	} else {
		  $existError = 1;
		  $errormessage = $errormessage."ieMD.xml fehlt";
    }
  }

  my @fileMDcheck = fileMDcheck($foldername);
  if ($fileMDcheck[0] ne "false"){
    printRep("$foldername: FileMetadaten für folgende Dateien gefunden:\n");
    foreach my $fileMDcheck (@fileMDcheck){
      printRep("\t".$fileMDcheck."\n");
    }
  }

  if (($existError != 0) || ($existWarning != 0)) {
    printRep($errormessage."\n");
  }
  if ($existError != 0) {
    #throw exception ifnot succesful
    return 1; #error
  } else {
    return 0; #only executed when all checks were successful
  }
}


###############################################################################
#subroutine creates CSV-File for the ingest into Rosetta
#returns int 0 when file was successfully created
#returns int 1 when csv could not be created
sub createCSV{
  #print "CSV wird erstellt\n";
  # vorbereiten der einzelnen Zeilen in Abhängigkeit der vorhandenen Metadaten
  # anschließend befüllen der Zeilen
	my $foldername = $_[0];
  my $existError = 0;
	my $errormessage = $foldername.": ";
	my @csv;
	my @csvLineHeaders;
	#my @csvLine;
	my @DCheaders;
	my @DCvalues;
  my @ColDCvalues;
	my $arrayLenght;
	my @sipLine,
	my @csvLineIE;
  my @csvLineCollection;

  #create header for collection.xml
  if (-f $foldername."/collection.xml") {
    my $dom = XML::LibXML->load_xml(no_cdata => 0, location => $foldername."/collection.xml");
    my $nodes= $dom->findnodes( "collections/collection/*");
    foreach my $node (@$nodes){
      my $attribute = 0;
      if ($node->hasAttributes()){
        my @attributes = $node->attributes();
        foreach my $att (@attributes){
          $attribute = $att;
        }
      }
      my $header = makeHeader($node->nodeName, $attribute, "0");
    	push (@DCheaders, $header);
		my $colContent = makeContent($node);
		push (@ColDCvalues, $colContent);
	}
  }
  my $ColCount = @ColDCvalues;

	#read in dc.XML
	my $filename = $foldername.'/dc.xml';
	my $dom = XML::LibXML->load_xml(no_cdata => 0,location => $filename);
	my $nodes= $dom->findnodes( $dcXmlHeadElement);
  if (scalar @$nodes == 0){
    $existError = 1;
    $errormessage = $errormessage."headelement in der dc.xml stimmt nicht mit dem in der config.json überein";
  }
	foreach my $node (@$nodes){
    my $attribute = 0;
    if ($node->hasAttributes()){
      my @attributes = $node->attributes();
      foreach my $att (@attributes){
        $attribute = $att;
      }
    }
    my $header = makeHeader($node->nodeName, $attribute, "0");
  	push (@DCheaders, $header);
	my $content = makeContent($node);
		push (@DCvalues, $content);
	}

  #fill sourceMD if available
	my @headerSourceMD;
	my @iESourceMDs;
	while ((my $sourceMDFile, my $sourceMDType) = each %sourceMD){
    if ($sourceMDFile ne "keine"){
    		my $ieSourceMD = fillSourceMD($foldername,$sourceMDFile,$sourceMDType);
		    push(@headerSourceMD, 'IE Source Metadata Content');
		    push (@iESourceMDs, $ieSourceMD);
    }
	}
  #fill out if ieMD - Metadata in IE Row
  my @headerIeMD;# = ('Primary Seed URL','WCT Identifier','Target Name','Group','Harvest Date','Harvest Time');
  my @allIeMD;
  if ($ieMD eq "true") {
    my $filename = $foldername.'/ieMD.xml';
  	my $dom = XML::LibXML->load_xml(no_cdata => 0, location => $filename);
  	my $nodes= $dom->findnodes("metadata/*");
  	foreach my $node (@$nodes){
      my $header = $node->nodeName;
      if ($header eq "oaiObjectIdentifier"){
        $header = "OAI (Object Identifier - IE)";
      } elsif ($header eq "urnObjectIdentifier"){
        $header = "URN (Object Identifier - IE)";
      } elsif ($header eq "uriObjectIdentifier"){
        $header = "URI (Object Identifier - IE)";
      }else {
        $header =~ s/([A-Z][a-z])/ $1/g;
        $header =~ s/([a-z])([A-Z])/$1 $2/g;
        $header =~ s/^\s+//g;
      }
      push (@headerIeMD, ucfirst($header));
	  	my $ieContent = makeContent($node);
		push (@allIeMD, $ieContent);
	}
  }

  #fill out if fileMD
  my @headerFileMD; # aray with all the headers
  my @fileMDValues; # array of arrays, first element is filename, following array consists of values, mapped to the headers
  my @fileMDfiles = fileMDcheck($foldername); #array contains all filenames with associated fileMD.xml, or "false" if not fileMD
  if ($fileMDfiles[0] ne "false"){
    my $fileMDcount = scalar @fileMDfiles; #Anzahl aller Dateien, denen fileMDs zugewiesen sind
    #Schleife, für jede Datei im folder, der eine fileMD.xml zugewiesen ist
    for (my $i = 0; $i < $fileMDcount; $i++){
      my @arrValues;
      #füge Dateinamen als erstes Element hinzu
      push (@arrValues, $fileMDfiles[$i]);
      #fülle tempräre Header / Value Arrays mit den Werten aud der fileMD.xml aus
      my @hFtemp;
      my @aVtemp;
      my $dom = XML::LibXML->load_xml(location => $foldername."/".$fileMDfiles[$i].".fileMD.xml");
      my $nodes= $dom->findnodes( "fileMD/*");
      foreach my $node (@$nodes){
        my $attribute = 0;
        if ($node->hasAttributes()){
          my @attributes = $node->attributes();
          foreach my $att (@attributes){
            $attribute = $att;
          }
        }
        my $header = makeHeader($node->nodeName, $attribute, "1");
        push(@hFtemp, $header);
        my $filemdContent = makeContent($node);
        push(@aVtemp,$filemdContent);
      }
      #befüllen von @headerFileMD mit den Headern, @arrValues mit den Werten
      if (scalar @headerFileMD == 0){
        #print "neuer Header wird angelegt\n";
        push(@headerFileMD, @hFtemp);
        push(@arrValues, @aVtemp);
      } else {
        #print "bereits header vorhanden\n";
        my $headerFcount = scalar @headerFileMD;
        for (my $i = 0; $i < $headerFcount; $i++){
          #sobald ein Element im hFtemp übereinstimmt, lege die Werte jeweils ab
          my $position = 0;
          until (($position==scalar @hFtemp)||($headerFileMD[$i] eq $hFtemp[$position])){
            $position++;
          }
          #setze den Wert von aVtemp auf die gefundene position
          $arrValues[$i+1] = $aVtemp[$position];
          #entferne header und value aus temporären arrays
          splice(@hFtemp,$position,1);
          splice(@aVtemp,$position,1);
        }
        if (scalar @hFtemp >0){ #nachdem alle vorhandenen Header zugeordnet sind, werden nun alle restlichen, neuen hinzugefügt
          push(@headerFileMD, @hFtemp);
          push(@arrValues, @aVtemp);
        }
      }
    my $ref = \@arrValues;
    push (@fileMDValues, $ref);
    }
  }

	#make array for first line of CSV
	@csvLineHeaders = ('Object Type','Title (DC)');
	push (@csvLineHeaders, @DCheaders);
	push (@csvLineHeaders, @variableHeaders);
  if (@headerIeMD){
    push (@csvLineHeaders, @headerIeMD);
  }
	if (@headerSourceMD) {
    push (@csvLineHeaders, @headerSourceMD);
  }
  if (@headerFileMD){
    push (@csvLineHeaders, @headerFileMD);
  }

  my @lastelements;
  #fill Label to @csvLineHeaders if available
  if ($subfoldersAsLabel eq "true") {
    push (@lastelements, 'File Label');
  }
  if ($checksums[0] ne "keine"){
    push (@lastelements, $checksums[2]);
  }
  push (@lastelements,'Preservation Type','Revision Number','Usage Type');
  push (@lastelements,'File Original Path','File Original Name');


	push (@csvLineHeaders, @lastelements);
	push(@csv,[@csvLineHeaders]);
	#save lenght of array for the other arrays
	$arrayLenght = @csvLineHeaders;

	#make SIP-line of csv
	@sipLine[$arrayLenght] = undef;
	@sipLine[0] = "SIP";
	@sipLine[1] = "$foldername";
	push(@csv,[@sipLine]);

  #make line for collection if collection.dc is available
  if (-f $foldername."/collection.xml"){
    @csvLineCollection[$arrayLenght] = undef;
  	@csvLineCollection[0] = "Collection";
    for (my $i = 0; $i<$ColCount; $i++){
        @csvLineCollection[$i+2] = $ColDCvalues[$i];
    }
  	push(@csv,[@csvLineCollection]);
  }

	#make array for IE
	@csvLineIE = ('IE',undef);
  if (-f "${foldername}/collection.xml"){
    my @emptyCells;
    @emptyCells[$ColCount-1] = undef;
    push (@csvLineIE, @emptyCells);
  }
	push (@csvLineIE, @DCvalues);
	push (@csvLineIE, @variableIEValues);
  if (@allIeMD){
    push (@csvLineIE, @allIeMD);
  }

	if (@iESourceMDs) {
    push (@csvLineIE, @iESourceMDs);
  }

	my @ieLastElements = (undef,undef,undef,undef,undef);
	push (@csvLineIE, @ieLastElements);
	push(@csv,[@csvLineIE]);

  #make array for representations and files
  while ((my $representation, my $isMandatory) = each %representations){
    if (-d "$foldername/$representation") {
      my @repLine = makeRepLine($representation,$arrayLenght);
      push(@csv,[@repLine]);
      #foreach file in representation make @csvLine
      my $path = $foldername."/".$representation."/";
      #my @files = File::Find::Rule->in($path);
      my @files;
      find( sub{ push @files, $File::Find::name }, $path);
      foreach my $file (@files){
        if (-f $file && $file !~ /.*\.fileMD.xml$/ && (($checksums[0] eq "separat" && $file !~ /.*$checksums[1]$/)||($checksums[0] ne "separat"))){
			  #hier fileMD rausuchen und übergeben, falls vorhanden
				  my @mdValues;
			  for (my $l = 0; $l< scalar @fileMDValues; $l++){
				if ($file =~ m/$fileMDValues[$l][0]/){
				  my $count = 1;
				  my $last_arr_index = $#{ $fileMDValues[$l] };
				  until ($count > $last_arr_index){
					push (@mdValues,$fileMDValues[$l][$count]);
					$count++;
				  }
				}
			  }
			  if (!@mdValues){
				@mdValues = undef;
			  }
			  #print Dumper @mdValues;
			  my @fileLine = makeFileLine($file,$arrayLenght,\@mdValues, scalar @headerFileMD);
			  push(@csv,[@fileLine]);
        }
      }
    }
  }

	#make csv
	my $csv = Text::CSV->new ( { binary => 1, eol =>"\r\n"} )
		or die "Cannot use CSV: ".Text::CSV->error_diag ();
	open my $fh, '> :utf8', "$foldername.csv" or die "$foldername.csv: $!";
	$csv->print ($fh, $_) for @csv;
	close $fh or die "$foldername.csv: $!";

	#change first line of CSV so that it does not contain any quotes
	my $CSVfilename = "$foldername.csv";
	open my $in_fh, '< :utf8', $CSVfilename
	  or warn "Cannot open $CSVfilename for reading: $!";
	my $first_line = <$in_fh>;
	$first_line =~ s/"//g;

	open my $out_fh, '> :utf8', "$CSVfilename.tmp"
	  or warn "Cannot open $CSVfilename.tmp for writing: $!";

	print {$out_fh} $first_line;
	print {$out_fh} $_ while <$in_fh>;

	close $in_fh;
	close $out_fh;

	# overwrite original with modified copy
	rename "$CSVfilename.tmp", $CSVfilename
	  or warn "Failed to move $CSVfilename.tmp to $CSVfilename: $!";


  #ExceptionHandling
  if ($existError != 0) {
    #throw exception ifnot succesful
    printRep($errormessage."\n");
    return 1; #error
  } else {
    return 0; #only executed when SIP creation was successful
  }
}

###############################################################################
#subroutine makes folderstructure for the ingest into Rosetta
#returns int 0 when folder were successfully arranged
#returns int 1 when error occured
sub mkFolders{
	my $foldername = $_[0];
  my $existError = 0;
	my $errormessage = $foldername.": ";
	my $sipFolder = "SIP_".$foldername;

	#erstelle Ordner content und Streams
	my $fcontent = $sipFolder."/content";
	my $fstreams = $fcontent."/streams/";
	my $forig = $fstreams."/".$foldername;

	unless(-d $sipFolder) {
		mkdir $sipFolder or die $!;
	}
	unless(-d $fcontent) {
		mkdir $fcontent or die $!;
	}
	unless(-d $fstreams) {
		mkdir $fstreams or die $!;
	}
	unless(-d $forig) {
		mkdir $forig or die $!;
	}

	#move csv-file
	my $from = $foldername.".csv";
	my $to = $fcontent."/".$foldername.".csv";
	my $returnValueCopyCSV = move $from, $to;
	#move Representations
  while ((my $representation, my $isMandatory) = each %representations){
		if (-d "$foldername/$representation") {
			my $dfrom = $foldername."/".$representation;
			my $dto = $forig."/".$representation;
			my $returnvalueMove = dircopy($dfrom,$dto);
			if ($returnvalueMove <= 1){
				$existError = 1;
				$errormessage = $errormessage."files were not moved";
			}
      #delete md5-files in representations if "separat"
      if ($checksums[0] eq "separat"){
        #my @files = File::Find::Rule->in($dto);
        my @files;
        find( sub{ push @files, $File::Find::name }, $dto);
        #foreach files in the directory (recursively)
        foreach my $file (@files) {
          if ($file =~ m/.$checksums[1]$/ && -f $file){
            unlink $file;
          }
        }
      }
      #delete fileMD-files in representations
      my @files;
      find( sub{ push @files, $File::Find::name }, $dto);
      #foreach files in the directory (recursively)
      foreach my $file (@files) {
        if ($file =~ m/.fileMD.xml$/ && -f $file){
          unlink $file;
        }
      }
		}
	}
  #ExceptionHandling
  if ($existError != 0) {
    #throw exception ifnot succesful
    printRep($errormessage."\n");
		rmdir -r $sipFolder;
    return 1; #error
  } else {
    return 0; #only executed when SIP creation was successful
  }
}

###############################################################################
#subroutine makes CSV line for Representations,
#changes foldername MASTER to correct Representation name for Rosetta "PRESERVATION_MASTER"
#returns CSV line for representations
sub makeRepLine{
	my $representation = $_[0];
	if ($representation eq "MASTER"){
		$representation = "PRESERVATION_MASTER"
	}
	my $arrayLenght = $_[1];
	my @repLine;
	@repLine[$arrayLenght] = undef;
	@repLine[0] = "REP";
	@repLine[$arrayLenght-5] = $representation;
	@repLine[$arrayLenght-4] = '1';
	@repLine[$arrayLenght-3] = 'VIEW';
	return @repLine;
}

###############################################################################
#subroutine makes CSV line for Files,
#returns CSV line for Files
sub makeFileLine{
	my $file = $_[0];
  $file = decode('UTF-8', $file);
	my ($filename,$path) = fileparse($file);
	my $arrayLenght = $_[1];
  my @fileMDValues = @{$_[2]};
  my $position = $_[3];
	my @fileLine;
	@fileLine[$arrayLenght] = undef;
	@fileLine[0] = "FILE";
  if ($position > 1) {
    if ($checksums[0] eq "keine" && $subfoldersAsLabel eq "false"){
      $position = $position+5;
    } elsif ($checksums[0] ne "keine" && $subfoldersAsLabel eq "true"){
      $position = $position+7;
    } else {
      $position = $position+6;
    }
    $position = $arrayLenght-$position;
    unless (scalar @fileMDValues == 1 && !$fileMDValues[0]){
      for (my $i = 0; $i <scalar @fileMDValues; $i++){
        #print $position." : ".@fileMDValues[$i]."\n";
        splice (@fileLine, $position, 0, $fileMDValues[$i]);
        $position++;
      }
    }
  }

	@fileLine[$arrayLenght-1] = $filename;
	@fileLine[$arrayLenght-2] = $path;

  ##if subfoldersAsLabel set Label
  my @Label = split(/\//,$path);
  ##wenn letzter Order != mögliche Repräsentation, dann als Label
  if ($subfoldersAsLabel eq "true" && defined $Label[2]){
      if ($checksums[0] eq "keine"){
        @fileLine[$arrayLenght-6] = $Label[2];
      } else {
        @fileLine[$arrayLenght-7] = $Label[2];
      }
  }

  if ($checksums[0] eq "gesammelt"){
    @fileLine[$arrayLenght-6] = $files_md5s{$file};
    #print $file." : ".$files_md5s{$file}."\n";
  } elsif ($checksums[0] eq "separat"){
    my $checksumfile = $file.$checksums[1];
    my $filehandle;
    open $filehandle,"<",$checksumfile;
    my $md5 = <$filehandle>;
    close $filehandle;
    my @fileMd5 = split( " ", $md5, 2 );
    @fileLine[$arrayLenght-6] = $fileMd5[0];
  }
	return @fileLine;
}

###############################################################################
#subroutine fills XML in sourceMD
#returns $sourceMD
sub fillSourceMD {
	my $foldername = $_[0];
	my $filename = $_[1];
	my $temp = $_[2];
  my $MDType;
  my $encoding;
  ($MDType , $encoding) = split(/;/,$temp, 2);
	my $returnvalue;
	my $XML;
	my $pathSourceMD = $foldername."/SOURCE_MD/".$filename;

	my $firstLinesSourceMD = "<?xml version=\"1.0\" encoding=\"".$encoding."\"?>\r";
	$firstLinesSourceMD = $firstLinesSourceMD.q(<sourceMD>)."\r";
	$firstLinesSourceMD = $firstLinesSourceMD."<mdWrap MDTYPE=\"".$MDType."\">\r";
	$firstLinesSourceMD = $firstLinesSourceMD.q(<xmlData>)."\r";
	my $lastLinesSourceMD = "</xmlData>\r";
	$lastLinesSourceMD = $lastLinesSourceMD."</mdWrap>\r";
	$lastLinesSourceMD = $lastLinesSourceMD."</sourceMD>\r";

	#fill variable XML with the content of folder SOURCE_MD
	open(my $fh, "<:encoding(".$encoding.")", $pathSourceMD) or die "cannot open file $pathSourceMD";
	{
			local $/;
			$XML = <$fh>;
	}
	close($fh);
	$XML =~ s/<\?xml version="1\.0" encoding="$encoding"\?>//;
	$XML =~ s/\r//g;

	$returnvalue = $firstLinesSourceMD.$XML.$lastLinesSourceMD;
	return $returnvalue;
}

#####################################################################################
# subroutine counts files in folder
# returns the number of files
sub countfiles{
	my $dir = $_[0];
	my $path = getcwd;
	$path = $path."/".$dir;
	my $numAllFiles = 0;
	#my @files;
	#find( sub{ push @files, $File::Find::name if (-f $File::Find::name)}, $path);
  #my @files = File::Find::Rule->in($path);
  my @files;
  find( sub{ push @files, $File::Find::name if (-f $File::Find::name)}, $path);
	#foreach files in the directory (recursively)
	foreach my $file (@files) {
		$numAllFiles += 1;
	}
	#print "countfiles: ordner ".$dir." enthält: ".$numAllFiles."\n";
	return $numAllFiles;
}

#####################################################################################
# subroutine makes Rosetta-conformant Header for dc-elements
# returns the header
sub makeHeader{
  #hier dc und dterms unterscheiden können nach namespace
  #wenn type vergeben, wird das über attribute eingelesen,
  #Beispiel dc:identifier xsi:type="dcterms:ISSN" wird zu Identifier - ISSN (DC)
  my $nodeName = $_[0];
  my $attribute = $_[1];
  my $forFile = $_[2];
  my $name;
  my $namespace;
  my $header;
  if ($nodeName =~ m/:/) {
    ($namespace, $name) = split(/:/,$nodeName, 2);
    $namespace = " (".uc($namespace).")";
    #wenn xsiType vorhanden, dann den Namen auftrennen
    if ($attribute != 0){
      $attribute =~ s/^ xsi:type="(.*)"/$1/;
      $attribute =~ s/.*://;
      $namespace = " - ".$attribute.$namespace;
    }
    #$name trennen wenn Camel Style IsPartOf -> Is Part Of
    $name =~ s/([A-Z])/ $1/g;
    $header = ucfirst(($name)).$namespace;

  } else {
    $header = ucfirst($nodeName);
    $header =~ s/([A-Z][a-z])/ $1/g;
    $header =~ s/([a-z])([A-Z])/$1 $2/g;
	$header = $header." (DC)";
  }
  if ($forFile == 1){
      $header = "FILE - ".$header;
  }
  #führendes Leerzeichen entfernen
  $header =~ s/^\s+//g;
  return $header;
}

#####################################################################################
# subroutine makes content for XML-Elements, keeps CDATA-Tags
# returns the content
sub makeContent{
  my $node = $_[0];
  my $content;
  if($node->childNodes) {
        foreach my $child ($node->childNodes()) {
            if ($child->nodeType == XML::LibXML::XML_CDATA_SECTION_NODE) {
                $content .= $child->toString;
            } else {
                $content .= $child->textContent;
            }
        }
    } else {
        $content = $node->textContent;
    }
  return $content;
}


##############################################################
# subroutine print Report on Screen and in report.txt
sub printRep{
  my $message = $_[0];
  print $message;
  open(OUT, ">>report_SIP_Erstellung.txt") or die $!;
  print OUT $message;
  close(OUT);
}

#####################################################################################
# subroutine charachers in files for non-ascii-characters
# print and report non-ascii characters
# print and warn in utf-8 with 4 bytes
sub checkCharacters{
  my $file = $_[0];
  my $message = "";
  #open file line per line
  open (INFILE,'<:encoding(UTF-8)',$file);
  my @lines = <INFILE>;
  my $number = 1;
  foreach my $line (@lines){
    my $nonascii = $line;
    $nonascii =~ s/[[:ascii:]]*//g;
	  #if non-ascii, check how many bytes
	  if ($nonascii ne ""){
  		#look at each character separate
  		my @splitLine = split(//,$nonascii);
  		foreach my $char (@splitLine){
        $char = encode('UTF-8', $char);
  			#warn if 4 bytes
        if (length($char) > 3) {
          my $filename = $file;
          $filename =~ s/.*\///g;
          my $hexCode = $char;
          $hexCode =~ s/(.)/sprintf("%x",ord($1))/eg;
          $message = $message."\n--".$filename.", Zeile: ".$number.", Character in Hex: ".$hexCode;
        }
  		}
		}
	  $number++;
  }
	if ($message eq ""){
		$message = "ok";
	}
  #return "notok";
  return $message;
}


#####################################################################################
# subroutine checks if there are metadata to be added on file level
#these metadata shall be added my a file which is called: [filename].[extension].fileMD.xml
# returns a list of file names or false, if no fileMD
sub fileMDcheck{
  my $foldername = $_[0];
  my @return;
  #mache eine Liste von alles Files pro Repräsentationsordner
  while ((my $representation, my $isMandatory) = each %representations){
    my $dir = $foldername."/".$representation;
    my $path = getcwd;
    $path = $path."/".$dir;
    if (-d $path){
      my @files;
      find( sub{ push @files, $File::Find::name if (-f $File::Find::name)}, $path);
      #foreach files in the directory (recursively)
      foreach my $file (@files) {
        #für jedes File in der Liste prüfe, ob die Datei auf FileMD.xml endet
        if ($file =~ m/.*\.fileMD\.xml$/){
          #für alle Files, die auf fileMD.xml enden, prüfe ob andere dazugehöriges File vorhanden
          my $belongingFile = $file;
          $belongingFile =~ s/\.fileMD\.xml$//g;
          #wenn ja, dann hänge dies an return dran
          if (-f $belongingFile){
            $belongingFile =~ s/^.*?$foldername//g;
            push(@return, $belongingFile);
          } else {
            $file =~ s/^.*?$foldername//g;
            printRep("$foldername: keine passende Datei zu Filemetadaten $file gefunden\n");
          }
        }
      }
    }
  }
  #wenn am Ende return leer, dann ersetze durch "false"
  if (!@return){
    $return[0] = "false";
  }
  return @return;
}
