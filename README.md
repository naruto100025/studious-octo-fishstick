
***********************new simple program to test the download _webout********;

/* *filename _out _webout lrecl=32767 encoding="utf-8"; */
/*  */
/* data  _null_; */
/* 	file _webout lrecl=32767 encoding="utf-8"; */
/* 	put "HEllo sas"; */
/* run; */
/*  */
/*  */
/* ***********************2-new simple program to test the download _webout********; */
/*  */
/* filename myfile "/dib/projects/goaml/xml/RR2025_10005_20250929_062040.xml"; */
/*  */
/* data _null_; */
/*     INFILE  myfile ;  *recfm=n; */
/*     file _webout   lrecl=32760 encoding="utf-8"; */
/*     input; */
/*     put _infile_; */
/* run; */

*****************************************************************************;

*****************************************************************;
*     NAME: rr_goaml_xml                                        *
*    TITLE: Generate xml file                                   *
*    PROCS: SQL/JSON                                            *
*     DATA: source.fsc_party_dim_view                           *
*   AUTHOR: Leandro Gonçalves                                   *
*     DATE: 25/08/2020                                          *
*****************************************************************;

%global dcm_termstr uid pw control fileName filePath tokenfref;
%global current_user;   /* logged-in SVI user, sent by the custom control (&current_user=...) */
/*%let report_id=RR2025_10005;*/

/* %include "/dib/projects/goaml/goaml_autoexec.sas";
%include "&SAS_CUST_ROOT/programs/aml_autoexec_update_report_data.sas"; */

%include "/dib/projects/DIB/custom_ucmacros/dib_aml_autoexec.sas";
%amlauto;
%dib_aml_autoexec;


/* filename cst_auto filesrvc folderpath='/DIB/DIB Reports/Auto_Execute'
    filename='auto_execute.sas';
%include cst_auto; */

/* ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++- */

/* options mprint mlogic symbolgen; */
/* options source2; */
/* options notes; */

/* proc printto log="&SAS_CUST_ROOT/logs/xml_&report_id..log" new; */
/* run; */


%put &serverNm;
%put &SYSUSERID;

%macro FileAttribs(filename);           
  %local rc fid fidc CreateDT ModifyDT; 
  %global Bytes; 
  %let rc=%sysfunc(filename(onefile,&filename)); 
  %let fid=%sysfunc(fopen(&onefile));
     %if &fid ne 0 %then %do;  
  %let Bytes=%sysfunc(finfo(&fid,File Size (bytes)));   
  %let CreateDT=%sysfunc(finfo(&fid,Create Time));     
  %let ModifyDT=%sysfunc(finfo(&fid,Last Modified));    
  %let fidc=%sysfunc(fclose(&fid));    
  %let rc=%sysfunc(filename(onefile)); 
  %put NOTE: File size of &filename is &bytes bytes;    
  %put NOTE- Created &createdt;       
  %put NOTE- Last modified &modifydt;
     %end;
        %else %put &filename could not be open.;
%mend FileAttribs;

/* 1. Generate xml file */
/*%include "&SAS_CUST_ROOT/projects/common/goaml/programs/aml_generate_xml.sas";*/

%global xml_file;
%include "&SAS_CUST_ROOT/programs/aml_generate_xml.sas";


/* 1b. Rename the XML to: ReportType_ReportID_CaseID_ExportUser_V#.xml
       e.g. STR_RR2026_100047_202610158_noor.khaled_V1.xml
       ExportUser = the user who clicked Export XML.
       V# counts up per report: V1 on the first export, V2 on the next, ...
       The new name is used for the saved file, the SVI attachment and the download. */

/* Column in sar.rr_report that holds the case ID.
   The first name in the list that exists in sar.rr_report is used. */
%let case_id_columns = cases_id case_id;

%macro goaml_xml_name;
    %local dsid rc case_col case_id report_type i col http_rc export_user;

    %if %sysfunc(fileexist(&filePath.&fileName)) = 0 %then %do;
        %put WARNING: XML file &filePath.&fileName not found - file name not changed.;
        %return;
    %end;

    /* Report type = the code written in the XML <report_code> */
    %let report_type = &report_code_id;
    %if "&report_code_id" = "FFR_SAR" or "&report_code_id" = "FFR_STR" %then %let report_type = FFR;
    %else %if "&report_code_id" = "PNMR_SAR" or "&report_code_id" = "PNMR_STR" %then %let report_type = PNMRA;

    /* Find the case ID column in sar.rr_report */
    %let dsid = %sysfunc(open(sar.rr_report));
    %if &dsid > 0 %then %do;
        %do i = 1 %to %sysfunc(countw(&case_id_columns));
            %let col = %scan(&case_id_columns, &i);
            %if %length(&case_col) = 0 and %sysfunc(varnum(&dsid, &col)) > 0 %then %let case_col = &col;
        %end;
        %let rc = %sysfunc(close(&dsid));
    %end;

    %if %length(&case_col) = 0 %then
        %put WARNING: None of the columns (&case_id_columns) exist in sar.rr_report - case ID set to NOCASE.;

    proc sql noprint;
        select %if %length(&case_col) %then cats(&case_col); %else ' ';
        into :case_id trimmed
        from sar.rr_report
        where rr_report_id = "&report_id";
    quit;

    /* Export user: ask Viya who is running this job (can't be changed from the browser) */
    %let http_rc = 0;
    filename _curusr temp;
    proc http url="&serverNm/identities/users/@currentUser" proxyhost=""
        out=_curusr
        method="get"
        oauth_bearer=sas_services;
        headers "Accept"="application/json";
    quit;
    %if %symexist(SYS_PROCHTTP_STATUS_CODE) %then %let http_rc = &SYS_PROCHTTP_STATUS_CODE;

    %if &http_rc = 200 %then %do;
        libname _curusr json fileref=_curusr;
        %if %sysfunc(libref(_curusr)) = 0 %then %do;
            data _null_;
                set _curusr.root;
                call symputx('export_user', id);
            run;
            libname _curusr clear;
        %end;
    %end;
    filename _curusr clear;

    /* Fallback (applied in the data step below): the user sent by the custom control */
    %if %length(&export_user) %then %put NOTE: Export user from Viya = &export_user;
    %else %if %length(%superq(current_user)) %then
        %put WARNING: Could not get the current user from Viya (HTTP &http_rc) - using current_user sent by the control.;
    %else %put WARNING: No current user available - user set to NOUSER.;

    data _null_;
        length fname $512 rid type casepart userraw userpart newname $256 oldpath newpath $1024;

        /* Keep each part file-name safe: characters not allowed in file names and spaces become _ */
        rid      = strip(symget('report_id'));
        type     = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(symget('report_type')));
        casepart = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(symget('case_id')));
        userraw  = strip(symget('export_user'));
        if userraw = '' then userraw = strip(symget('current_user'));
        userpart = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(userraw));
        if casepart = '' then casepart = 'NOCASE';
        if userpart = '' then userpart = 'NOUSER';

        /* Next version = highest existing _V# for this report in the xml folder + 1 */
        max_ver = 0;
        rc  = filename('xmldir', strip(symget('filePath')));
        did = dopen('xmldir');
        if did > 0 then do;
            do i = 1 to dnum(did);
                fname = dread(did, i);
                if find(fname, cats('_', rid, '_'), 'it') > 0
                   and prxmatch('/_V\d+\.xml$/i', strip(fname)) then
                    max_ver = max(max_ver, input(prxchange('s/^.*_V(\d+)\.xml$/$1/i', 1, strip(fname)), 8.));
            end;
            rc = dclose(did);
        end;
        rc = filename('xmldir');

        newname = cats(catx('_', type, rid, casepart, userpart, cats('V', max_ver + 1)), '.xml');
        oldpath = cats(symget('filePath'), symget('fileName'));
        newpath = cats(symget('filePath'), newname);

        rc = rename(oldpath, newpath, 'file');
        if rc = 0 then do;
            call symputx('fileName', newname, 'G');
            put 'NOTE: XML file renamed to ' newname;
        end;
        else put 'WARNING: Could not rename XML file to ' newname ' - keeping ' oldpath;
    run;

    %put NOTE: fileName=&fileName;
%mend goaml_xml_name;

%goaml_xml_name;




/* 2. Get access token */
/* %include "&SAS_CUST_ROOT/projects/common/goaml/programs/aml_credentials.sas";*/


/* 3. Get File UUID */
filename response temp;
proc http url="&serverNm/folders/folders/@item?path=/visual-investigator" proxyhost=""
  /*in=payload*/ 
  out=response
  method="get"
  ct="application/json; text/plain"
  oauth_bearer=sas_services;
headers "Accept"="application/json";
	debug level=3;
quit;

libname step1 json (response);

data _null_;
	set step1.links;
	if(method="GET" and rel="self") then do;
		call symput("fileUUID", compress(href));
	end;
run;
%put "fileUUID= &fileUUID";
/* /folders/folders/2b3517a5-6db9-4644-a318-69a55687cf16 */
/* /files/files/2766cc85-9a78-4ffb-9c0c-cac2f981b405 */




/* 4.Upload file to the File Service */
/*filename response temp;*/


/*filename respons '/customer/projects/amluat/goaml/json/response1.json';*/

filename respons temp;

filename upFileN "&filePath.&fileName";
proc http url="&serverNm/files/files?parentFolderUri=&fileUUID" proxyhost=""
  in=upFileN
  out=respons
  method="post"
  ct="application/json; text/plain"
  oauth_bearer=sas_services;
	headers
		"Content-Type"="application/xml" 
		"Accept"="application/json,application/xml;q=0.9,*/*;q=0.8"
		"Content-Disposition"="attachment; filename=&fileName"
	;
	debug level=2;
quit;





/* 5. Get File Service Details */
libname step2 json (respons);
%FileAttribs(&filePath.&fileName);
data _null_;
	set step2.root;
	call symput("fileId", id);
	call symput("fileLocation", cat("/files/files/",id,"/content"));
	call symput("fileSize", compress("&bytes"));
run;

%put &fileId;
%put &fileLocation;
%put &fileSize;
%put &fileName;
%put &bytes;






/* 6. Upload file from File Service to VI */
filename meta temp;
proc json out=meta pretty nosastags;
	write open object;
		write values "id" "&fileId";
		write values "name" "&fileName";
		write values "location" "&fileLocation";
		write values "type" "text/xml";
		write values "size" &fileSize;
		write values "description" "GoAML File - &report_id";
	write close;
run;

proc http url="&serverNm/svi-datahub/documents/rr_report/&report_id/attachments" proxyhost=""
  in=meta

  /*out=_webout*/
  method="post"
  ct="application/json; text/plain"
  oauth_bearer=sas_services;
	headers
		"Content-Type"="application/json;charset=UTF-8" 
		"Accept"="application/json, text/plain, */*"
	;
	debug level=2;
quit;


/* 7. Return the XML to the browser with its original file name */
 filename xml "&FILEPATH./&fileName";

%put "&FILEPATH./&fileName";

/* Send the XML as a download named exactly &fileName (e.g. RR2025_10005_20250929_062040.xml).
   name= must stay "_webout.xml" so the job streams the result back to the custom control. */
filename _webout filesrvc parenturi="&SYS_JES_JOB_URI"
  name="_webout.xml"
  contenttype="application/xml"
  contentdisp="attachment; filename=""&fileName""";

data _null_;
    INFILE  xml ;  *recfm=n;
    file _webout lrecl=32760 encoding="utf-8";
    input;
    put _infile_;
run;

