# CSV-Ingest generisch

(English Version below)

Das Skript erstellt eine CSV und die Ordnerstruktur für den Ingest.
Der erstellte Ordner kann über einen Submission Job geingestet werden.
Die Konfiguration wird über Config.json mitgegeben.

## Voraussetzungen
Die Dateien liegen geordnet vor:
* ein Ordner pro IE
* ein Unterordner nach den Repräsentationen benannt
* in dem Unterordner die jeweiligen Dateien
* eine dc.xml mit den deskriptiven Metadaten im IE-Ordner
* eine collection.xml, wenn die IE eine oder mehrerer Collections zugeordnet wird
* eine ieMD.xml, wenn weitere Metadaten auf IE-Ebene mitgegeben werden sollen (z.B. aus einem Harvest oder CMS-Record-IDs)
* eine checksums.md5 (oder andere Dateiendung), wenn Checksummen vorhanden sind, alternativ je Datei eine Datei mit [Dateiname].[Dateiendung].[Checksummenformat]
* eine [Dateiname].[Dateiendung].fileMD.xml, wenn Metadaten auf File-Ebene mitgegeben werden sollen																					   
* Source-Metadaten liegen im Ordner SOURCE_MD
```
Ordner
|  
+--IE1  
|  |  
|  +--dc.xml  
|  +--[ieMD.xml]  
|  +--[collection.xml]  
|  +--[checksum.md5]  
|  |--MASTER  
|  |  |  
|  |  + Datei1.pdf  
|  |  + [Datei1.pdf.md5]  
|  |  + [Datei1.pdf.fileMD.xml]							 
|  |  + Datei2.pdf  
|  |  \ [Datei2.pdf.md5]  
|  |  
|  |--[DERIVATIVE_COPY]  
|  |  |  
|  |  + Datei3.pdf  
|  |  \ [Datei3.pdf.md5]  
|  |  
|  \--[SOURCE_MD]  
|     |  
|     \ Dateiname.xml  
|  
+--[IE2]  
+--[IE3]  
+--[checksums.md5]  
+--config.json  
\--makeSIPs.pl  
```



## Skript ausführen
Das Skript kann lokal oder auf dem Server genutzt werden.
Aufruf des Skriptes erfolgt mit folgenden Kommandozeilenparametern:   
`perl makeSIP.pl`   
`--inputfolder "/c/path/to/dir"`   
gibt den Pfad zu den Paketen an, die gepackt werden sollen

`--configfile "/c/path/to/Config.json"`      
gibt die Config.json an, diese kann nun auch variabel benannt werden, z.B. nach Producer / Material Flow

`--outputfolder "/c/path/to/outputdir"`  
gibt den Pfad an, an dem der Output (SIPs und Report) weggeschrieben werden, erstellt einen neuen Ordner, falls noch nicht vorhanden. Falls im angegebenen Ordner Dateien vorhanden sind, wird abgebrochen, um keine Pakete zu überschreiben





### Welche Metadaten werden in welche Konfigurationsdatei übergeben?

* Config.json

	- dc:rights
    - dcterms:accessRights
    - User Defined Fields		   
    - IE Entity Type
    - dcterms:license
    - Source Metadata
    - Repräsentationen
    - ieMD-Datei vorhanden
    - Checksums vorhanden


* ieMD.xml
    - Web Harvest Section
    - Object Identifier
    - CMS Section
    - Retention Policy
    - Submission Reason


## Config.json
Die Konfigurationsdatei ist im JSON-Format, und kann per Editor geändert werden.

### Access Rights
Wird nun ausschließlich über den Material Flow geregelt.

### DC Rights
Beispiele:  
`"dcRights" : "Rechteangabe"` 
`"dcRights" : null`  

Der Wert für dc:rights kann für alle IEs in der Config.json angegeben werden. Wenn für jedes Paket individuell ein dc:rights vergeben werden soll, so muss dies in der dc:xml mitgegeben werden. Der Wert für dctermsAccessrights in der Config.json wird mit "null" ausgefüllt. 

### DC Terms Access Rights
Beispiele:  
`"dctermsAccessRights" : "AccessRights"` 
`"dctermsAccessRights" : null`  

Der Wert für dcterms:accessrights kann für alle IEs in der Config.json angegeben werden. Wenn für jedes Paket individuell ein dcterms:accessrights vergeben werden soll, so muss dies in der dc:xml mitgegeben werden. Der Wert für dctermsAccessrights in der Config.json wird mit "null" ausgefüllt.  

### User Defined Felder
Beispiel:  
`"userDefinedA" : "Digitalisat",`  
`"userDefinedB" : null,`

Beide Werte müssen immer übergeben werden. Wenn das userDefinedB nicht ausgefüllt werden soll, dann null eintragen.

### IE Entity ieEntity
Beispiel:  
`"ieEntityType" : "Digitalisat",`  

### DC Terms License
Beispiele:  
`"dctermsLicense" : "OA_mit_CC_Lizenz",  
"dctermsLicense" : null`  

Der Wert für dcterms:license kann für alle IEs in der Config.json angegeben werden. Wenn für jedes Paket individuell ein dcterms:license vergeben werden soll, so muss dies in der dc:xml mitgegeben werden. Der Wert für dctermsLicense in der Config.json wird mit "null" ausgefüllt.  

### dcXML Head Element
Beispiel:  
`"dcXmlHeadElement" : "/srw_dc:dc/*",`  

Damit verschiedene Versionen von DC-XML-Dateien unterstützt werden, muss die Schreibweise des dc-Head-Elements (root-Element der dc.xml) angegeben werden. Es werden sowohl DC-Elemente als auch DCTerms-Elemente übergeben, hierzu muss bei beiden der Namespace angegeben werden.
Die XML-Datei zum Beispiel sieht wie folgt aus:  
`<srw_dc:dc xmlns:srw_dc="info:srw/schema/1/dc-schema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:srw/schema/1/dc-schema http://www.loc.gov/standards/sru/resources/dc-schema.xsd">`  
`  <dc:title xmlns="http://purl.org/dc/elements/1.1/">Operations research</dc:title>`  
`  <dcterms:isPartOf>Journal of Mathemtics/2020/02/01</dcterms:isPartOf>`  
`</srw_dc:dc>`  

### Source Metadata  
Beispiel 1:  
`"sourceMD":`  
`  { "marc.xml" : "MARC;UTF-8"},`  
Beispiel 2:  
`"sourceMD":`  
`  { "marc.xml" : "MARC;UTF-8" , "mods.xml" : "MODS;UTF-8"},`  
Beispiel 3:  
`"sourceMD":`
`  { "keine" : null},`  
Beispiel 4:  
`"sourceMD":`
`  { "conservationMD.xml" : "OTHER\" OTHERMDTYPE=\"DelftConservationMetadata;UTF-8"},`  

Es können alle von Rosetta nativ unterstützten Source Metadaten übergeben werden. Hierzu wird jeweils der Dateiname sowie der MetadataType und Zeichenkodierung angegeben. MetadataType und Zeichenkodierung werden mit Anführungszeichen und mit Trennsymbol ; übergeben (siehe Beispiele).
Es können auch mehr als eine SourceMD-Datei mitgegeben werden (siehe Beispiel 2).
Wenn keine Source Metadaten übergeben werden sollen, ist es wie in Beispiel 3 anzugeben.
Wenn Sourcemetadaten vom Typ "OTHER" übergeben werden sollen, dann muss dies wie in Beispiel 4 übergeben werden (also mit \ vor den "). Zusätzlich muss in Rosetta (Admin -> Code Tables -> Other Source Metadata Subtype) hinterlegt werden, dass es einen Other SourceMetadata Type gibt der mit dem OTHERMDTYPE übereinstimmt (im Beispiel DelftConservationMetadata).

### Representations
Beispiel:  
`"representations" :    { "MASTER" : "mandatory" , "DERIVATIVE_COPY" : "optional"},`  

Es können beliebig viele Representations mitgegeben werden, sofern sie in Rosetta hinterlegt sind.
Es wird für jede Repräsentation mitgegeben, ob die verpflichtend vorhanden sein muss ("mandatory"), oder optional vorliegen darf ("optional").
	Achtung: wenn eine Repräsentation nicht angegeben ist, dann wird diese auch nicht übernommen.																						   


### Subfolders als Label
Beispiel:  
`"subfoldersAsLabel" : "true",`  
`"subfoldersAsLabel" : "false",`

Unterordner in Repräsentationsordnern können dafür genutzt werden, Dateien mit einem Label zu verzeichnen, dafür wird in der Config.json "true" hinterlegt. Der Ordnername entspricht damit dem Labelnamen, z.B: wird bei der Datei "MASTER/supplement/Arikel1_Supplement.pdf" der Label "supplement" vergeben.  
Wenn in den Repräsentationen Unterordner vorhanden sind, welche als Unterordner in Rosetta aufgenommen werden sollen, dann wird in der Config.json "false" hinterlegt. IEs können bei dieser Einstellung keine Labels erhalten.

### Metadaten auf IE Ebene
Beispiel:  
`"ieMD" : "true",`  
`"ieMD" : "false",`

Wenn Metadaten auf IE-Ebene mitgegeben werden, welche keine DC oder DC Terms Elemente sind, kann die ieMD.xml mitgegeben werden. Ein Beispiel findet sich unter Beispiele/komplett_mit_md5_pro_file/Test.  Die IE-Metadaten können u.a. genutzt werden für __Harvest Metadaten__ und __Angaben zum CMS Enrichment (CMS Record ID und CMS System)__.

`<?xml version='1.0' encoding='UTF-8' standalone='no'?>  `  
`<metadata>  `  
`	<primarySeedURL>URL</primarySeedURL>  `  
`	<WCTIdentifier>Skriptname Version 1.2</WCTIdentifier>  `  
`	<targetName>JSPEC</targetName>  `  
`	<group>Publisher</group> `
` <harvestDate>2021-05-12 17:21:59</harvestDate>  `   
`</metadata>`  


### Prüfsummen
Beispiel 1:  
`"checksums" : [ "separat",".md5","MD5" ]`  
Beispiel 2:  
`"checksums" : [ "gesammelt","Dateiname.md5","MD5" ]`  
Beispiel 3:  
`"checksums" : [ "keine" ]`  

Prüfsummen können, müssen aber nicht übergeben werden.
Es können entweder in einer Datei auf Ebene der makeSIP.pl alle Prüfsummen für die IEs vorhanden sein ("gesammelt", Beispiel 2), dann wird der Dateiname übergeben, und der Prüfsummentyp.
Es können auch eine Prüfsummendatei pro Datei vorliegen ("separat", Beispiel 1), dann wird die Dateiendung der Prüfsummendatei angegeben, und der Prüfsummentyp.
Wichtiger Hinweis für die Prüfsummendatei: nur einfacher Zeilenumbruch (Linux-Style), Trennezichen zwischen Prüfsumme und Datei ist ein Tab, Pfadangaben/mit/diesen/Schrägstrichen!

### collection.xml
Eine IE kann einer Collection zugewiesen werden. Hierfür wird ein XML mit folgendem Aufbau benötigt:  
`<?xml version='1.0' encoding='UTF-8' standalone='no'?>  `  
`<collections xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">  `  
`  <collection>`
`    <dcterms:isPartOf>Open Access E-Journals/</dcterms:isPartOf>`
`    <dc:title>Examplejournal</dc:title>`
`    <dc:identifier xsi:type="dcterms:ISSN">Online: 1234-1234</dc:identifier>`
`  </collection>`
`  <collection>`
`    <dcterms:isPartOf>Open Access E-Journals/Examplejournal</dcterms:isPartOf>`
`    <dc:title>vol 1</dc:title>`
`    <dc:date>2026</dc:date>`
`  </collection>`
`  <collection>`
`    <dcterms:isPartOf>Open Access E-Journals/Examplejournal/vol 1</dcterms:isPartOf>`
`    <dc:title>issue 1</dc:title>`
`  </collection>`
`</collections>`  

Für die collection wird ein <collection>-Tag angelegt. Die Metadaten auf Collection-Ebene werden als dc / dcterms - Metadaten abgelegt. Verpflichtend sind Angaben zu dc:title (Name der Collection) und dc:isPartOf.    
Die DC-Metadaten auf Collection-Ebene werden beim erstmaligen Anlegen der Collection abgelegt und werden danach NICHT überschrieben / ergänzt.    
Beispiel: Auf Ebene der Collection "Examplejournal" wird die ISSN als dc:identifier übergeben und in Rosetta abgelegt. Wenn bei einem weiteren Ingest / anderen SIP die dc:publisher in der collection.xml steht (und somit auch in der CSV), so wird dieses NICHT in Rosetta ergänzt.
ACHTUNG: Collections dürfen keinen "/" im Titel haben - bitte ersetzen durch ein passendes Sonderzeichen: " : " bei Titelzusatz, " = " bei Paralleltiteln
### deskriptive Metadaten auf File Ebene

Mit einer zusätzlichen XML auf Ebene des Files können FileMetadaten mitgegeben werden. Die XML wird dabei wie folgt benannt:  
[Dateiname].[Dateiendung].fileMD.xml  
Als Filemetadaten können weiter dc-/dcterms-Elemente übergeben werden, aber auch andere Metadaten wie Label und Note. Für eine komplette Übersicht der möglichen Filemetadaten kann man in Rosetta schauen unter Management -> Deposit -> CSV-Template.  



# CSV Ingest generic (english version of README)

The script creates a CSV and the folder structure for the ingest.
The created folder can be tested via a submission job.
The configuration is provided via Config.json.

## Prerequisites
The files are available in an folderstructure:
* one folder per IE
* one subfolder named after the representations
* the respective files in the subfolder
* a dc.xml with the descriptive metadata in the IE folder
* a collection.xml, if the IE is assigned to one or more collections
* an ieMD.xml if further metadata should be included on IE level (e.g. from a harvest or CMS record IDs)
* a checksums.md5 (or other file extension) if checksums are present, alternatively one file with [filename].[file extension].[checksum format] per file.
																					   
* Source metadata is located in the folder SOURCE_MD
```
folder
|  
+--IE1  
| |  
| +--dc.xml  
| +--[ieMD.xml]  
| +--[collection.xml]  
| +--[checksum.md5]  
| |--MASTER  
| | |  
| + [file1.pdf  
| | + [file1.pdf.md5]  
| + [File1.pdf.fileMD.xml]							 
| + file2.pdf  
| | [File2.pdf.md5]  
| |  
| |--[DERIVATIVE_COPY]  
| | |  
| + file3.pdf  
| | \ [file3.pdf.md5]  
| |  
| \--[SOURCE_MD]  
| |  
| \ filename.xml  
|  
+--[IE2]  
+--[IE3]  
+--[checksums.md5]  
+--config.json  
\--``--makeSIPs.pl  
```



## Run script
The script can be used locally or on the server.
The script is called with the following command line parameters:
									   

																																									  
`perl makeSIP.pl`
`--inputfolder "/c/path/to/dir"`
Specifies the path to the packages to be packed

`--configfile "/c/path/to/Config.json"`
specifies the Config.json, which can now also be named variably, e.g. Producer / Material Flow

`--outputfolder "/c/path/to/outputdir"`
Specifies the path where the output (SIPs and report) is to be saved, creates a new folder if it does not already exist. If there are files in the specified folder, it is cancelled so as not to overwrite any packages




### What metadata is passed to which configuration file?

* Config.json

	- dc:rights
    - dcterms:accessRights
    - User Defined Fields
    - IE Entity Type
    - User Defined Fields
    - Access Right Policy ID
    - dcterms:license
    - Source Metadata
    - Representations
    - ieMD file available
    - Checksums present


* ieMD.xml
    - Web Harvest Section
    - Object Identifier
    - CMS Section
    - Retention Policy
    - Submission Reason


## Config.json
The configuration file is in JSON format, and can be changed using an editor.

### Access Rights
Is now controlled exclusively via the material flow.
						   

### DC Rights
Examples:  
`"dcRights" : "Rights information"`
`"dcRights" : null`

The value for dc:rights can be specified for all IEs in Config.json. If a dc:rights is to be assigned individually for each package, this must be specified in the dc:xml. The value for dctermsAccessrights in Config.json is filled in with "null".

### DC Terms Access Rights
Examples:  
`"dctermsAccessRights" : "AccessRights"`
`"dctermsAccessRights" : null`

The value for dcterms:accessrights can be specified for all IEs in Config.json. If a dcterms:accessrights is to be assigned individually for each package, this must be specified in the dc:xml. The value for dctermsAccessrights in Config.json is filled in with "null".  
																																																																			 

### User Defined Fields
Example:  
`"userDefinedA" : "Digitalisat",`  
`"userDefinedB" : null,`

Both values must always be passed. If the userDefinedB is not to be filled in, then enter null.

### IE Entity ieEntity
Example:  
`"ieEntityType" : "Digitized",`  

### DC Terms License
Examples:  
`"dctermsLicense" : "OA_with_CC_License",  
"dctermsLicense" : null`.  

The value for dcterms:license can be specified for all IEs in Config.json. If a dcterms:license is to be assigned individually for each package, this must be specified in the dc:xml. The value for dctermsLicense in Config.json is filled with "null".  

### dcXML Head Element
Example:  
`"dcXmlHeadElement" : "/srw_dc:dc/*",`.  

To support different versions of DC XML files, the notation of the dc head element (root element of dc.xml) must be specified. Both DC elements and DCTerms elements are passed, for this the namespace must be specified for both.
For example, the XML file looks like this:  
`<srw_dc:dc xmlns:srw_dc="info:srw/schema/1/dc-schema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:srw/schema/1/dc-schema http://www.loc.gov/standards/sru/resources/dc-schema.xsd">`  
` <dc:title xmlns="http://purl.org/dc/elements/1.1/">Operations research</dc:title>`  
` <dcterms:isPartOf>Journal of Mathemtics/2020/02/01</dcterms:isPartOf>`  
`</srw_dc:dc>`  

### Source Metadata  
Example 1:  
`"sourceMD":`  
` {"marc.xml" : "MARC;UTF-8"},`  
Example 2:  
`"sourceMD":`  
` { "marc.xml" : "MARC;UTF-8" , "mods.xml" : "MODS;UTF-8"},`  
Example 3:  
`"sourceMD":`
` `"none" : null},`  
Example 4:  
`"sourceMD":`
															
		  
			 
					
		  
			 
` { "conservationMD.xml" : "OTHER\" OTHERMDTYPE=\"DelftConservationMetadata;UTF-8"},` `  

All source metadata natively supported by Rosetta can be passed. For this purpose, the filename as well as the MetadataType and character encoding are specified in each case. MetadataType and character encoding are passed with quotes and with separator symbol ; (see examples).
More than one SourceMD file can be supplied (see example 2).
If no source metadata is to be passed, it must be specified as in Example 3.
If source metadata of type "OTHER" is to be passed, then this must be passed as in Example 4 (i.e. with \ in front of the "). Additionally, in Rosetta (Admin -> Code Tables -> Other Source Metadata Subtype) it must be specified that there is an Other SourceMetadata Type that matches the OTHERMDTYPE (in the example DelftConservationMetadata).

### Representations
Example:  
`"representations" : { "MASTER" : "mandatory" , "DERIVATIVE_COPY" : "optional"},`  

Any number of representations can be supplied, as long as they are stored in Rosetta.
For each representation it is specified whether it must be present ("mandatory"), or whether it may be present ("optional").
																		   


### Subfolders as label
Example:  
`"subfoldersAsLabel" : "true",` `  
`"subfoldersAsLabel" : "false",`

Subfolders in representation folders can be used to mark files with a label, for this "true" is deposited in the Config.json. The folder name then corresponds to the label name, e.g. the file "MASTER/supplement/Arikel1_Supplement.pdf" is assigned the label "supplement".  
If there are subfolders in the representations, which should be included as subfolders in Rosetta, then "false" is stored in Config.json. IEs cannot get labels with this setting.

### Metadata at IE level.
Example:  
`"ieMD" : "true",`  
`"ieMD" : "false",`

If IE-level metadata is supplied that is not a DC or DC Terms element, ieMD.xml can be supplied. See examples/complete_with_md5_pro_file/test for an example.  The IE metadata can be used for __Harvest Metadata__ and __Information about CMS Enrichment (CMS Record ID and CMS System)__, among other things.

`<?xml version='1.0' encoding='UTF-8' standalone='no'?> `  
`<metadata> `  
` <primarySeedURL>URL</primarySeedURL> `  
` <WCTIdentifier>script name version 1.2</WCTIdentifier> `  
` <targetName>JSPEC</targetName> `  
` <group>Publisher</group> `
` <harvestDate>2021-05-12 17:21:59</harvestDate> `   
`</metadata>`  


### Checksums
Example 1:  
`"checksums" : [ "separate",".md5", "MD5" ]`  
Example 2:  
`"checksums" : [ "collected", "filename.md5", "MD5" ]`  
Example 3:  
`"checksums" : [ "none" ]`  

Checksums can, but do not have to be passed.
Either all checksums for the IEs can be present in a file at the makeSIP.pl level ("collected", example 2), in which case the filename is passed, and the checksum type.
There can also be one checksum file per file ("separate", example 1), then the file extension of the checksum file is given, and the checksum type.
Important note for the checksum file: only single line break (Linux style), separator between checksum and file is a tab, path specifications/with/these/slashes!

### collection.xml
An IE can be assigned to a collection. This requires an XML with the following structure:  
`<?xml version='1.0' encoding='UTF-8' standalone='no'?> `  
`<collections xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"> `  
` <collection> `  
` <dcterms:isPartOf>OpenAccess-ejournals/Hindawi/Journal of Automated Methods and Management in Chemistry</dcterms:isPartOf> `  
` <dc:title>2010</dc:title> `  
` <dc:identifier xsi:type="dcterms:ISSN">0000-9999</dc:identifier> `  
` </collection>`  
`</collections>`  

A <collection> tag is created for the collection. The IE level metadata is stored as dc / dcterms - metadata. Mandatory are information about dc:title (name of the collection) and dc:isPartOf (further parent collections, currently available are "IWF" and "OpenAccess-ejournals").

### Checksums
Example 1:  
`"checksums" : [ "separate",".md5", "MD5" ]`  
Example 2:  
`"checksums" : [ "collected", "filename.md5", "MD5" ]`  
Example 3:  
`"checksums" : [ "none" ]`  

Checksums can, but do not have to be passed.
Either all checksums for the IEs can be present in a file at the makeSIP.pl level ("collected", example 2), in which case the filename is passed, and the checksum type.
There can also be one checksum file per file ("separate", example 1), then the file extension of the checksum file is given, and the checksum type.
Important note for the checksum file: only single line break (Linux style), separator between checksum and file is a tab, path specifications/with/these/slashes!

### collection.xml
An IE can be assigned to a collection. This requires an XML with the following structure:
`<?xml version='1.0' encoding='UTF-8' standalone='no'?> `
`<collections xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"> `
` <collection>`
` <dcterms:isPartOf>Open Access E-Journals/</dcterms:isPartOf>`
` <dc:title>Examplejournal</dc:title>`
` <dc:identifier xsi:type="dcterms:ISSN">Online: 1234-1234</dc:identifier>`
` </collection>`
` <collection>`
` <dcterms:isPartOf>Open Access E-Journals/Examplejournal</dcterms:isPartOf>`
` <dc:title>vol 1</dc:title>`
` <dc:date>2026</dc:date>`
` </collection>`
` <collection>`
` <dcterms:isPartOf>Open Access E-Journals/Examplejournal/vol 1</dcterms:isPartOf>`
` <dc:title>issue 1</dc:title>`
` </collection>`
`</collections>`

A <collection> tag is created for the collection. The metadata at collection level is stored as dc / dcterms metadata. Information on dc:title (name of the collection) and dc:isPartOf is mandatory.    
The DC metadata at collection level is stored when the collection is created for the first time and is NOT overwritten / supplemented afterwards.    
Example: At the level of the "Examplejournal" collection, the ISSN is transferred as dc:identifier and stored in Rosetta. If the dc:publisher is in the collection.xml for another ingest / another SIP (and therefore also in the CSV), this is NOT added in Rosetta.
ATTENTION: Collections must not have a "/" in the title - please replace with a suitable special character: " : " for title addition, " = " for parallel titles
### descriptive metadata at file level

With an additional XML on the level of the file, file metadata can be provided. The XML is named as follows:  
[filename].[file extension].fileMD.xml  
As file metadata further dc-/dcterms elements can be passed, but also other metadata like label and note. For a complete overview of the possible file metadata you can look in Rosetta under Management -> Deposit -> CSV-Template. 

## Authors

* **Merle Friedrich** - *German Nation Library of Science and Technology (TIB)*

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
