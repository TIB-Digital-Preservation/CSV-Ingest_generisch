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
use File::Path qw(rmtree);				  
use JSON;
use Data::Dumper;
use Cwd;
use utf8;
use Encode;
binmode STDOUT, ":utf8";    # for output
use Getopt::Long;
my $version = "1.7";

#print instructions
print "CSV-Ingest_generisch Version: ".$version."\n";
print "Das Skript erstellt eine CSV und die Ordnerstruktur für den Ingest.
Der erstellte Ordner kann über einen Submission Job geingestet werden.
Die Konfiguration wird über Config.json mitgegeben. Siehe auch README.MD\n";
print "------------------------------------------\n";
print "---START----------------------------------\n";
my $inputfolder;
my $configfile;
my $outputfolder;
GetOptions(
    'inputfolder=s' => \$inputfolder, #=S with a string
    'configfile=s' => \$configfile,
    'outputfolder=s' => \$outputfolder
) or die 'unbekannte(r) Parameter\n';
die('Parameter fehlt: --inputfolder "/cygdrive/u/path/to/dir"\n') unless defined $inputfolder;
die('Parameter fehlt: --configfile "/cygdrive/u/path/to/Config.json"\n') unless defined $configfile;
die('Parameter fehlt: --outputfolder "/cygdrive/u/path/to/outputdir"\n') unless defined $outputfolder;

#check inputparameter
die 'inputfolder '.$inputfolder.' fehlt."\n'
  unless (-d $inputfolder);
die 'configfile '.$configfile.' fehlt."\n'
  unless (-f $configfile);
if (-d $outputfolder){
    my $numFiles = countfiles($outputfolder);
    #Abbrechen, wenn der Ordner bereits Dateien enthält
    if ($numFiles > 0){
        die 'outputfolder '.$outputfolder.' enthält bereits Dateien."\n'
    }
} else {
    mkdir $outputfolder or die $!;
    print "outputfolder ".$outputfolder." angelegt\n";
}

#read in folders
my @allFoldersLong = grep { -d } glob($inputfolder."/*");
#in allFolder werden nur die Ordnername gespeichert, z.B. "Beispiel", "123456"
my @allFolders;
foreach my $folder (@allFoldersLong){
    my $folder = fileparse($folder);
    push (@allFolders, $folder);
}
my @filesComplete;
my @csvCreated;
my @createdSIPs;
my %files_md5s;

my $config;
{
  local $/; #Enable 'slurp' mode
  open my $fh, "<", $configfile;
  $config = <$fh>;
  close $fh;
}
my $configParams = decode_json($config);

my $dcRights = $configParams->{'dcRights'};
my $dctermsAccessRights = $configParams->{'dctermsAccessRights'};
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
my $checksumsRegex;

my @variableHeaders = ('Rights (DC)','Access Rights (DCTERMS)','IE User Defined A','IE User Defined B','IE Entity Type',"License (DCTERMS)");
my @variableIEValues = ($dcRights,$dctermsAccessRights,$userDefinedA,$userDefinedB,$ieEntityType,$dctermsLicense);

#wenn nur eine Datei für Checksums vorliegt einen Hash erstellen
if ($checksums[0] eq "gesammelt"){
  #check if file exists
  my $checksumfile = $checksums[1];
  if (-f $inputfolder."/".$checksumfile){
    my $filehandle;
    open $filehandle,"<",$inputfolder."/".$checksumfile;
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
} elsif ($checksums[0] eq "separat"){
    $checksumsRegex = "\\".$checksums[1];
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
			printRep($folder.": ERROR: es fehlen Dateien, die verpflichtend sind oder diese sind fehlerhaft\n\n");
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
	my $path = $inputfolder;
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
	foreach my $file (@files) {
	}
  #Repräsentationen prüfen, anhand der Angabe ob mandatory oder optional unterscheiden zw. Warnung und Fehler
  while ((my $representation, my $isMandatory) = each %representations){
    #wenn Ordner vorhanden ist, aber keine Dateien darin, dann liegt ein Fehler vor
    if (-d "$path/$representation"){
      my $num_files = countfiles("$path/$representation");
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
		  # wenn File in Representation       UND ist ist ein file UND endet nicht auf fileMDxml
		  if ($file =~ m/$foldername\/$representation/ && -f $file && $file !~ /.*\.fileMD.xml$/ ){
			if ($checksums[0] eq "gesammelt"){
			  #check if exists for each file otherwise error
			  my $path = $inputfolder;
			  $file =~ s/$path\///;
			  unless ($files_md5s{$file}){
				$existError = 1;
				$errormessage = $errormessage."Checksum für  ".$file." fehlt, ";
			  }
			} elsif ($checksums[0] eq "separat" && $file !~ /.*$checksumsRegex$/){
			  #check if file exists otherwise error
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

	if (-f "$path/dc.xml"){
		my $messCharac = checkCharacters("$path/dc.xml");
		if ($messCharac ne "ok"){
			$existError = 1;
			$errormessage = $errormessage.$messCharac;
		}
    my $parser = XML::LibXML->new;
    my $xml = eval { $parser->parse_file("$path/dc.xml") };
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
  if (-f "$path/collection.xml"){
	   my $messCharac = checkCharacters("$path/collection.xml");
	   if ($messCharac ne "ok"){
		      $existError = 1;
		      $errormessage = $errormessage.$messCharac;
	   }
     if (-z "$path/collection.xml"){
       $existError = 1;
       $errormessage = $errormessage."collection.xml ist eine leere Datei, ";
     }
     printRep($foldername.": collection.xml vorhanden\n");
  }

  #check if ieMD exist
  if ($ieMD eq "true") {
    if (-f "$path/ieMD.xml"){
		my $messCharac = checkCharacters("$path/ieMD.xml");
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
				  
	my $arrayLenght;
	my @sipLine,
	my @csvLineIE;
  my @csvLineCollection;

  #create header for collection.xml
  my @headerColMD; # array with all the headers
  my @colMDValues; # array of arrays, arrays consists of values, mapped to the headers
  my $colCount = 0;
  if (-f "${inputfolder}/${foldername}/collection.xml") {
    my $dom = XML::LibXML->load_xml(no_cdata => 0, location => $inputfolder."/".$foldername."/collection.xml");
    my $nodes= $dom->findnodes( "collections/collection"); #pro collection einzeln
	foreach my $node (@$nodes) {
	  $colCount++;
      my @arrValues;
		#fülle temporäre Header / Value Arrays mit den Werten aud der fileMD.xml aus
      my @hColTemp;
      my @vColTemp;
      my $nodesDC= $node->findnodes("*");
      foreach my $nodeDC (@$nodesDC){
        my $attribute = 0;
        if ($nodeDC->hasAttributes()){
          my @attributes = $nodeDC->attributes();
          foreach my $att (@attributes){
            $attribute = $att;
          }
        }
        my $header = makeHeader($nodeDC->nodeName, $attribute, "0");
        push(@hColTemp, $header);
        my $colMdContent = makeContent($nodeDC);
        push(@vColTemp,$colMdContent);
      }
	#befüllen von @headerColMD mit den Headern, @arrValues mit den Werten
      if (scalar @headerColMD == 0){
        #print "neuer Header wird angelegt\n";
        push(@headerColMD, @hColTemp);
        push(@arrValues, @vColTemp);
      } else {
        #print "bereits header vorhanden\n";
        my $headerCount = scalar @headerColMD;
        for (my $i = 0; $i < $headerCount; $i++){
          #sobald ein Element im hColTemp übereinstimmt, lege die Werte jeweils ab
          my $position = 0;
          until (($position==scalar @hColTemp)||($headerColMD[$i] eq $hColTemp[$position])){
            $position++;
          }
          #setze den Wert von vColTemp auf die gefundene position
          $arrValues[$i] = $vColTemp[$position];
          #entferne header und value aus temporären arrays
          splice(@hColTemp,$position,1);
          splice(@vColTemp,$position,1);
        }
        if (scalar @hColTemp >0){ #nachdem alle vorhandenen Header zugeordnet sind, werden nun alle restlichen, neuen hinzugefügt
          push(@headerColMD, @hColTemp);
          push(@arrValues, @vColTemp);
        }
      }
    my $ref = \@arrValues;
    push (@colMDValues, $ref);
    }
   }
    my $colCountColums = scalar @headerColMD;


	#read in dc.XML
	my $filename = $inputfolder."/".$foldername.'/dc.xml';
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
    # pruefe ob in dc oder dcterms vorhanden
    if (isValidDc($node->nodeName) == 1){
        my $header = makeHeader($node->nodeName, $attribute, "0");
  	    push (@DCheaders, $header);
	    my $content = makeContent($node);
		push (@DCvalues, $content);
	} else {
	    $existError = 1;
	    $errormessage = $errormessage." ".$node->nodeName." ist kein valides DC / DCterms Element";
    }
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
    my $filename = $inputfolder."/".$foldername.'/ieMD.xml';
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
  my @headerFileMD; # array with all the headers
  my @fileMDValues; # array of arrays, first element is filename, following array consists of values, mapped to the headers
  my @fileMDfiles = fileMDcheck($foldername); #array contains all filenames with associated fileMD.xml, or "false" if not fileMD
  if ($fileMDfiles[0] ne "false"){
    my $fileMDcount = scalar @fileMDfiles; #Anzahl aller Dateien, denen fileMDs zugewiesen sind
    #Schleife, für jede Datei im folder, der eine fileMD.xml zugewiesen ist
    for (my $i = 0; $i < $fileMDcount; $i++){
      my @arrValues;
      #füge Dateinamen als erstes Element hinzu
      push (@arrValues, $fileMDfiles[$i]);
      #fülle temporäre Header / Value Arrays mit den Werten aud der fileMD.xml aus
      my @hFtemp;
      my @aVtemp;
      my $dom = XML::LibXML->load_xml(location => $inputfolder."/".$foldername."/".$fileMDfiles[$i].".fileMD.xml");
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
	push (@csvLineHeaders, @headerColMD);
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
  if (-f "${inputfolder}/${foldername}/collection.xml"){
    for (my $i = 0; $i<$colCount; $i++){
        @csvLineCollection[$arrayLenght] = undef;
  	    @csvLineCollection[0] = "Collection";
        for (my $c = 0; $c<$colCountColums; $c++){
            @csvLineCollection[$c+2] = $colMDValues[$i][$c];
        }
    push(@csv,[@csvLineCollection]);
    }
								   
  }

	#make array for IE
	@csvLineIE = ('IE',undef);
  if (-f "${inputfolder}/${foldername}/collection.xml"){
    my @emptyCells;
    @emptyCells[$colCountColums-1] = undef;
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
    if (-d "${inputfolder}/${foldername}/${representation}") {
      my @repLine = makeRepLine($representation,$arrayLenght);
      push(@csv,[@repLine]);
      #foreach file in representation make @csvLine
      my $path = $inputfolder."/".$foldername."/".$representation."/";
											   
      my @files;
      find( sub{ push @files, $File::Find::name }, $path);
      foreach my $file (@files){
        if (-f $file && $file !~ /.*\.fileMD.xml$/ && (($checksums[0] eq "separat" && $file !~ /.*$checksumsRegex$/)||($checksums[0] ne "separat"))){
        $file =~ s/$inputfolder\///;
        print $file."\n";
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
	my $csv = Text::CSV->new ( { binary => 1, eol =>"\n"} )
		or die "Cannot use CSV: ".Text::CSV->error_diag ();
	my $csvOutputTemp = $outputfolder."/".$foldername."_temp.csv";
	open my $fh, '> :utf8', $csvOutputTemp or die "$csvOutputTemp: $!";
	$csv->print ($fh, $_) for @csv;
	close $fh or die "$csvOutputTemp: $!";

	#change first line of CSV so that it does not contain any quotes
	my $CSVfilename = $csvOutputTemp;
										
	open my $in_fh, '< :utf8', $CSVfilename or warn "Cannot open ".$CSVfilename." for reading: $!";
	my $first_line = <$in_fh>;
	$first_line =~ s/"//g;

    my $csvOutput = $outputfolder."/".$foldername.".csv";
	open my $out_fh, '> :utf8', $csvOutput or warn "Cannot open ".$csvOutput." for writing: $!";
														  

	print {$out_fh} $first_line;
	while (<$in_fh>) {
	    my $line = $_;
	    $line =~ s/\r//g;
	    print {$out_fh} $line;
	}

	close $in_fh;
	close $out_fh;

										
										
																 


  #ExceptionHandling
  if ($existError != 0) {
    #throw exception if not succesful
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
	my $sipFolder = $outputfolder."/SIP_".$foldername;

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
	my $from = $outputfolder."/".$foldername.".csv";
	my $to = $fcontent."/".$foldername.".csv";
	my $returnValueCopyCSV = move $from, $to;
	if ($returnValueCopyCSV == 0){
				$existError = 1;
				$errormessage = $errormessage."CSV-File was not moved";
    } else {
        unlink($outputfolder."/".$foldername."_temp.csv");
    }

	#move Representations
  while ((my $representation, my $isMandatory) = each %representations){
		if (-d "$inputfolder/$foldername/$representation") {
			my $dfrom = $inputfolder."/".$foldername."/".$representation;
			my $dto = $forig."/".$representation;
			my $returnvalueMove = dircopy($dfrom,$dto);
			if ($returnvalueMove <= 1){
				$existError = 1;
				$errormessage = $errormessage."files were not moved";
			}
      #delete checksum-files in representations if "separat"
      if ($checksums[0] eq "separat"){
												
        my @files;
        find( sub{ push @files, $File::Find::name }, $dto);
        #foreach files in the directory (recursively)
        foreach my $file (@files) {
          if ($file =~ m/$checksumsRegex$/ && -f $file){
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
    #throw exception if not succesful
    printRep($errormessage."\n");
    rmtree $sipFolder or warn "Could not remove $sipFolder";
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
    my $checksumfile = $inputfolder."/".$file.$checksums[1];
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
	my $pathSourceMD = $inputfolder."/".$foldername."/SOURCE_MD/".$filename;

	my $firstLinesSourceMD = "<?xml version=\"1.0\" encoding=\"".$encoding."\"?>\n";
	$firstLinesSourceMD = $firstLinesSourceMD.q(<sourceMD>)."\n";
	$firstLinesSourceMD = $firstLinesSourceMD."<mdWrap MDTYPE=\"".$MDType."\">\n";
	$firstLinesSourceMD = $firstLinesSourceMD.q(<xmlData>)."\n";
	my $lastLinesSourceMD = "</xmlData>\n";
	$lastLinesSourceMD = $lastLinesSourceMD."</mdWrap>\n";
	$lastLinesSourceMD = $lastLinesSourceMD."</sourceMD>\n";

	#fill variable XML with the content of folder SOURCE_MD
	open(my $fh, "<:encoding(".$encoding.")", $pathSourceMD) or die "cannot open file $pathSourceMD";
	{
			local $/;
			$XML = <$fh>;
	}
	close($fh);
	$XML =~ s/<\?xml version="1\.0" encoding="$encoding".*\?>//;
				 

	$returnvalue = $firstLinesSourceMD.$XML.$lastLinesSourceMD;
	return $returnvalue;
}

#####################################################################################
# subroutine counts files in folder
# returns the number of files
sub countfiles{
    my $path = $_[0];
				   
						
    my $numAllFiles = 0;
    my @filesCount;
    find( sub{ push @filesCount, $File::Find::name if (-f $File::Find::name)}, $path);
										   
			
																			   
    #foreach files in the directory (recursively)
    foreach my $fileCounted (@filesCount) {
        $numAllFiles += 1;
    }
																   
    return $numAllFiles;
}

#####################################################################################
# subroutine makes Rosetta-conformant Header for dc-elements
# returns the header
sub makeHeader{
  #hier dc und dterms unterscheiden können nach namespace
  #wenn type vergeben, wird das über attribute eingelesen,
  #Beispiel dc:identifier xsi:type="dcterms:ISSN" wird zu Identifier - ISSN (DC)
  #Beispiel dc:language xsi:type=“dcterms:ISO639-3 wird zu Identifier - ISO 639-3 (DC)
  my $nodeName = $_[0];
  my $attribute = $_[1];
  my $forFile = $_[2];
  my $name;
  my $namespace;
  my $header;
  #wenn in einer datei dc und dcterms elemente vorhanden sind, sind diese als namespance durch : abgetrennt
  if ($nodeName =~ m/:/) {
    ($namespace, $name) = split(/:/,$nodeName, 2);
    $namespace = " (".uc($namespace).")";
    #wenn xsiType vorhanden, dann den Namen auftrennen, xsi:type DOI wird von Rosetta nicht unterstützt
    if (($attribute != 0) && ($attribute !~ m/.*DOI.*/)){
      $attribute =~ s/^ xsi:type="(.*)"/$1/;
      $attribute =~ s/.*://;
      $attribute =~ s/DCMI(.*)/DCMI $1/;
      $attribute =~ s/ISO(.*)/ISO $1/;
      $attribute =~ s/RFC(.*)/RFC $1/;
      $attribute =~ s/W3CDTF/W 3 CDTF/;
      $namespace = " - ".$attribute.$namespace;
    }
    #$name trennen wenn Camel Style IsPartOf -> Is Part Of
    $name =~ s/([A-Z])/ $1/g;
    $header = ucfirst(($name)).$namespace;

  } else {
    $header = ucfirst($nodeName);
    $header =~ s/([A-Z][a-z])/ $1/g;
    $header =~ s/([a-z])([A-Z])/$1 $2/g;
						   
  }
  if (($forFile == 1) && ($header =~ m/.*\(DC.*/)){
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
  open(OUT, ">>".$outputfolder."/report_SIP_Erstellung.txt") or die $!;
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
    my $path = $inputfolder;
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
            $belongingFile =~ s/^.*?$foldername\/$representation/$representation/g;
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
#####################################################################################
# subroutine checks if there are metadata to be added on file level
#these metadata shall be added my a file which is called: [filename].[extension].fileMD.xml
# returns a list of file names or false, if no fileMD
sub isValidDc{
    my $dcTag = $_[0];
    my %dcTags = ("dcterms:abstract" => "valid",
        "dcterms:accessRights" => "valid",
        "dcterms:accrualMethod" => "valid",
        "dcterms:accrualPeriodicity" => "valid",
        "dcterms:accrualPolicy" => "valid",
        "dcterms:alternative" => "valid",
        "dcterms:audience" => "valid",
        "dcterms:available" => "valid",
        "dcterms:bibliographicCitation" => "valid",
        "dcterms:conformsTo" => "valid",
        "dcterms:coverage" => "valid",
        "dcterms:created" => "valid",
        "dcterms:creator" => "valid",
        "dcterms:date" => "valid",
        "dcterms:dateAccepted" => "valid",
        "dcterms:dateCopyrighted" => "valid",
        "dcterms:dateSubmitted" => "valid",
        "dcterms:description" => "valid",
        "dcterms:educationLevel" => "valid",
        "dcterms:extent" => "valid",
        "dcterms:format" => "valid",
        "dcterms:hasFormat" => "valid",
        "dcterms:hasPart" => "valid",
        "dcterms:hasVersion" => "valid",
        "dcterms:identifier" => "valid",
        "dcterms:instructionalMethod" => "valid",
        "dcterms:isFormatOf" => "valid",
        "dcterms:isPartOf" => "valid",
        "dcterms:isReferencedBy" => "valid",
        "dcterms:isReplacedBy" => "valid",
        "dcterms:isRequiredBy" => "valid",
        "dcterms:issued" => "valid",
        "dcterms:isVersionOf" => "valid",
        "dcterms:language" => "valid",
        "dcterms:license" => "valid",
        "dcterms:mediator" => "valid",
        "dcterms:medium" => "valid",
        "dcterms:modified" => "valid",
        "dcterms:provenance" => "valid",
        "dcterms:publisher" => "valid",
        "dcterms:references" => "valid",
        "dcterms:relation" => "valid",
        "dcterms:replaces" => "valid",
        "dcterms:requires" => "valid",
        "dcterms:rights" => "valid",
        "dcterms:rightsHolder" => "valid",
        "dcterms:source" => "valid",
        "dcterms:spatial" => "valid",
        "dcterms:subject" => "valid",
        "dcterms:tableOfContents" => "valid",
        "dcterms:temporal" => "valid",
        "dcterms:title" => "valid",
        "dcterms:type" => "valid",
        "dcterms:valid" => "valid",
        "dc:coverage" => "valid",
        "dc:creator" => "valid",
        "dc:contributor" => "valid",
        "dc:date" => "valid",
        "dc:description" => "valid",
        "dc:format" => "valid",
        "dc:identifier" => "valid",
        "dc:language" => "valid",
        "dc:publisher" => "valid",
        "dc:relation" => "valid",
        "dc:rights" => "valid",
        "dc:source" => "valid",
        "dc:subject" => "valid",
        "dc:title" => "valid",
        "dc:type" => "valid",
    );

    return exists($dcTags{$dcTag});
}