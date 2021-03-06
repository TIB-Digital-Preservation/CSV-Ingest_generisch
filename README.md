# CSV-Ingest generisch

Das Skript erstellt eine CSV und die Ordnerstruktur für den Ingest.
Der erstellte Ordner kann über einen Submission Job geingestet werden.
Die Konfiguration wird über Config.json mitgegeben.

## Voraussetzungen
Die Dateien liegen geordnet vor:
* ein Ordner pro IE
* ein Unterordner nach den Repräsentationen benannt, mit den entsprechenden Dateiendung
* eine dc.xml mit den deskriptiven Metadaten im IE-Ordner
* eine collection.xml, wenn die IE eine oder mehrerer Collections zugeordnet wird
* eine harvest.xml, wenn die Datei geharvested wurde und die Harvest-Section in der IE ausgefüllt werden soll
* eine checksums.md5 (oder andere Dateiendung), wenn Checksummen vorhanden sind, alternativ je Datei eine Datei mit [Dateiname].[Dateiendung].[Checksummenformat]
* Source-Metadaten liegen im Ordner SOURCE_MD

## Skript ausführen
Das Skript kann lokal oder auf dem Server genutzt werden.
Lokal: Bei Cygwin müssen einige Perl-Module installiert werden.
Server: auf dem Myapp ist Perl installiert.

Config.json und makeSIPs.pl liegen im selben Ordner wie die zu packenden Pakete. Auf dem Server kann das Skript per Kommandozeile mit folgendem Befehl aufgerufen werden:
`perl makeSIP.pl`

## Config.json
Die Konfigurationsdatei ist im JSON-Format, und kann per Editor geändert werden.

### Access Rights
Beispiel:  
`"accessRight" : "16728",`

Für die Access Rights muss die ID angegeben werden, dies bedeutet auch, dass für DEV, TEST und PROD andere IDs vergeben werden müssen.

### User Defined Felder
Beispiel:  
`"userDefinedA" : "MFO_ODA_Digitalisat",`  
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

Damit verschiedene Versionen von DC-XML-Dateien unterstützt werden, muss die Schreibweise des dc-Head-Elements angegeben werden. Es werden sowohl DC-Elemente als auch DCTerms-Elemente übergeben, hierzu muss bei beiden der Namespace angegeben werden.
Die XML-Datei zum Beispiel sieht wie folgt aus:  
`<srw_dc:dc xmlns:srw_dc="info:srw/schema/1/dc-schema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:srw/schema/1/dc-schema http://www.loc.gov/standards/sru/resources/dc-schema.xsd">`  
`  <dc:title xmlns="http://purl.org/dc/elements/1.1/">Operations research</dc:title>`  
`  <dcterms:isPartOf>Journal of Mathemtics/2020/02/01</dcterms:isPartOf>`  
`</srw_dc:dc>`  

### Source Metadata  
Beispiel 1:  
`"sourceMD":`  
`  { "marc.xml" : "MARC"},`  
Beispiel 2:  
`"sourceMD":`  
`  { "marc.xml" : "MARC" , "mods.xml" : "MODS"},`  
Beispiel 3:  
`"sourceMD":`
`  { "keine" : null},`  
Beispiel 4:  
`"sourceMD":`
`  { "conservationMD.xml" : "OTHER\" OTHERMDTYPE=\"DelftConservationMetadata"},`  

Es können alle von Rosetta nativ unterstützten Source Metadaten übergeben werden. Hierzu wird jeweils der Dateiname sowie der MetadataType angegeben.
Es können auch mehr als eine SourceMD-Datei mitgegeben werden (siehe Beispiel 2).
Wenn keine Source Metadaten übergeben werden sollen, ist es wie in Beispiel 3 anzugeben.
Wenn Sourcemetadaten vom Typ "OTHER" übergeben werden sollen, dann muss dies wie in Beispiel 4 übergeben werden (also mit \ vor den "). Zusätzlich muss in Rosetta (Admin -> Code Tables -> Other Source Metadata Subtype) hinterlegt werden, dass es einen Other SourceMetadata Type gibt der mit dem OTHERMDTYPE übereinstimmt (im Beispiel DelftConservationMetadata).

### Representations
Beispiel:  
`"representations" :  ["MASTER","MODIFIED_MASTER" ],`  

Es können beliebig viele Representations mitgegeben werden, sofern sie in Rosetta hinterlegt sind.
Dabei ist es unerheblich, ob bei einer IE eine Representation nicht vorhanden ist.

### Subfolders als Label
Beispiel:  
`"subfoldersAsLabel" : "true",`  
`"subfoldersAsLabel" : "false",`

Unterordner in Repräsentationsordnern können dafür genutzt werden, Dateien mit einem Label zu verzeichnen, dafür wird in der Config.json "true" hinterlegt. Der Ordnername entspricht damit dem Labelnamen, z.B: wird bei der Datei "MASTER/supplement/Arikel1_Supplement.pdf" der Label "supplement" vergeben.  
Wenn in den Repräsentationen Unterordner vorhanden sind, welche als Unterordner in Rosetta aufgenommen werden sollen, dann wird in der Config.json "false" hinterlegt. IEs können bei dieser Einstellung keine Labels erhalten.

### Web Harvest
Beispiel:  
`"webHarvest" : "true",`  
`"webHarvest" : "false",`

Wenn die Dateien durch einen WebHarvester abgeholt wurden, können der IE Metadaten mitgegeben werden, die den Harvestvorgang beschreiben. Die Metadaten werden in einer harvest.xml pro IE übergeben.  

`<?xml version='1.0' encoding='UTF-8' standalone='no'?>  `  
`<harvest>  `  
`	<primatySeedURL>URL</primatySeedURL>  `  
`	<WCTIdentifier>Skriptname Version 1.2</WCTIdentifier>  `  
`	<targetName>JSPEC</targetName>  `  
`	<group>Hindawi</harvestDate>  `  
`	<harvestTime>11:36</harvestTime>`    
`</harvest>`  


### Prüfsummen
Beispiel 1:  
`"checksums" : [ "separat",".md5","MD5" ]`  
Beispiel 2:  
`"checksums" : [ "gesammelt","Dateiname.md5","MD5" ]`  
Beispiel 3:  
`"checksums" : [ "keine" ]`  

Prüfsummen können, müssen aber nicht übergeben werden.
Es können entweder in einer Datei alle Prüfsummen für eine IE vorhanden sein ("gesammelt", Beispiel 2), dann wird der Dateiname übergeben, und der Prüfsummentyp.
Es können auch eine Prüfsummendatei pro Datei vorliegen ("separat", Beispiel 1), dann wird die Dateiendung der Prüfsummendatei angegeben, und der Prüfsummentyp.
Wichtiger Hinweis für die Prüfsummendatei: nur einfacher Zeilenumbruch (Linux-Style), Trennezichen zwischen Prüfsumme und Datei ist ein Tab, Pfadangaben/mit/diesen/Schrägstrichen!

### collection.xml
Eine IE kann einer Collection zugewiesen werden. Hierfür wird ein XML mit folgendem Aufbau benötigt:  
`<?xml version='1.0' encoding='UTF-8' standalone='no'?>  `  
`<collections xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">  `  
`  <collection>  `  
`	  <dcterms:isPartOf>OpenAccess-ejournals/Hindawi/Journal of Automated Methods and Management in Chemistry</dcterms:isPartOf>  `  
`	  <dc:title>2010</dc:title>  `  
`	  <dc:identifier xsi:type="dcterms:ISSN">0000-9999</dc:identifier>  `  
`  </collection>`  
`</collections>`  

Für die collection wird ein <collection>-Tag angelegt. Die Metadaten auf IE-Ebene werden als dc / dcterms - Metadaten abgelegt. Verpflichtend sind Angaben zu dc:title (Name der Collection) und dc:isPartOf  (weitere übergeordnete Collections, aktuell sind vorhanden "IWF" und "OpenAccess-ejournals").

### deskriptive Metadaten auf File Ebene

Mit einer zusätzlichen XML auf Ebene des Files können FileMetadaten mitgegeben werden. Die XML wird dabei wie folgt benannt:  
[Dateiname].[Dateiendung].fileMD.xml  
Als Filemetadaten können weiter dc-/dcterms-Elemente übergeben werden, aber auch andere Metadaten wie Label und Note. Für eine komplette Übersicht der möglichen Filemetadaten kann man in Rosetta schauen unter Management -> Deposit -> CSV-Template.  

## Weitere Entwicklungmöglichkeiten:
* Werte über Webservice abprüfen
* Module erstellen für generische Aufgaben

## Authors
 
* **Merle Friedrich** - *German Nation Library of Science and Technology (TIB)*
 
## License
 
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
