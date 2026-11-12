
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

/* Timing: writes "NOTE: TIMING: <step> after N.N s" to the log, to see where the export time goes */
%global goaml_t0;
%let goaml_t0 = %sysfunc(datetime());
%macro goaml_timer(step);
    %put NOTE: TIMING: &step after %sysfunc(putn(%sysevalf(%sysfunc(datetime()) - &goaml_t0), 8.1)) s;
%mend goaml_timer;

/* Wait before this code started. The custom control sends the button-click time as &click_time
   (browser clock, milliseconds since 1970, UTC). SAS datetime() is the server clock, seconds since 1960. */
%global click_time;
%macro goaml_log_wait;
    %local click_utc start_utc;
    %if %length(%superq(click_time)) = 0 or %sysfunc(notdigit(%superq(click_time))) > 0 %then %do;
        %put NOTE: TIMING: no valid click_time from the control - wait before start not known.;
        %return;
    %end;
    %let click_utc = %sysevalf(&click_time / 1000 + 315619200);   /* 1970 -> 1960 epoch, UTC */
    %let start_utc = %sysfunc(tzones2u(&goaml_t0));                /* server local time -> UTC */
    %put NOTE: TIMING: button clicked   %sysfunc(putn(&click_utc, e8601dt23.3)) UTC (browser clock);
    %put NOTE: TIMING: SAS code started %sysfunc(putn(&start_utc, e8601dt23.3)) UTC (server clock);
    %put NOTE: TIMING: waited %sysfunc(putn(%sysevalf(&start_utc - &click_utc), 8.1)) s for the SAS server before the code started;
%mend goaml_log_wait;
%goaml_log_wait;
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
%goaml_timer(autoexec);

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

/* 0. Speed-up: copy this report's rows from the sar_* tables used by the XML_fetch_* functions
      into WORK once (one database query per table). The functions then read these small WORK
      tables instead of querying the database for every account, person, phone, address, ...
      in the report. If a WORK copy is missing, the functions fall back to the database.      */
%let goaml_preload_tables = sar_account sar_signatory sar_person sar_person_identification
                            sar_phone_number sar_address sar_company sar_ubo rr_report;

/* The XML_fetch_* functions are compiled once into func_lib - point SAS at them here,
   so the export does not need to recompile them */
libname func_lib "&SAS_CUST_ROOT/data";
options cmplib=func_lib.go_aml_functions;

%macro goaml_preload;
    %local i t;
    %do i = 1 %to %sysfunc(countw(&goaml_preload_tables));
        %let t = %scan(&goaml_preload_tables, &i);
        data work.&t(compress=char);
            set sar.&t(where=(rr_report_id = "&report_id"));
        run;
    %end;
%mend goaml_preload;

%goaml_preload;
%goaml_timer(copy report rows to WORK);


/* 1. Generate xml file */
/*%include "&SAS_CUST_ROOT/projects/common/goaml/programs/aml_generate_xml.sas";*/

%global xml_file;
%include "&SAS_CUST_ROOT/programs/aml_generate_xml.sas";
%goaml_timer(XML generation);

/* Remove the WORK copies made in step 0 */
proc datasets lib=work nolist nowarn;
    delete &goaml_preload_tables;
quit;


/* 1b. Name the XML: ReportType_CaseID_ReportID_ExportUser_V#.xml
       e.g. SAR_202610143_RR2026_100047_Latha.Kommoju@DIB.AE_V2.xml
       CaseID     = sar.rr_report.cases_id
       ReportID   = full report ID, or RR + year (RR2026_100047 -> RR2026) - see setting below
       ExportUser = the user who clicked Export XML
       V#         = counts up per report: V1 on the first export, V2 on the next, ...
                    (worked out from the XML files already attached to the report)
       The name is used for the SVI attachment and the download.
       The file saved in the xml folder keeps its original unique name (&xmlPath),
       because the new name is not unique across reports of the same case.        */
%global xmlPath;

/* Report ID part of the name: full = RR2026_100047, year = RR2026
   (must match fileNameReportId in the custom control) */
%let goaml_name_report_part = full;

%macro goaml_xml_name;
    %local case_id report_type http_rc export_user att_rc xml_count max_ver dsid has_name rc;

    %let xmlPath = &filePath.&fileName;
    %if %sysfunc(fileexist(&xmlPath)) = 0 %then %do;
        %put WARNING: XML file &xmlPath not found - file name not changed.;
        %return;
    %end;

    /* Report type = the code written in the XML <report_code> */
    %let report_type = &report_code_id;
    %if "&report_code_id" = "FFR_SAR" or "&report_code_id" = "FFR_STR" %then %let report_type = FFR;
    %else %if "&report_code_id" = "PNMR_SAR" or "&report_code_id" = "PNMR_STR" %then %let report_type = PNMRA;

    /* Case ID */
    proc sql noprint;
        select cats(cases_id) into :case_id trimmed
        from sar.rr_report
        where rr_report_id = "&report_id";
    quit;
    %if %length(&case_id) = 0 %then %put WARNING: cases_id is empty for &report_id - case ID set to NOCASE.;

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

    /* Versions already used: XML files attached to this report (this export is not attached yet) */
    %let xml_count = 0;
    %let max_ver   = 0;
    %let att_rc    = 0;
    filename _rratt temp;
    proc http url="&serverNm/svi-datahub/documents/rr_report/&report_id/attachments?limit=1000" proxyhost=""
        out=_rratt
        method="get"
        oauth_bearer=sas_services;
        headers "Accept"="application/json";
    quit;
    %if %symexist(SYS_PROCHTTP_STATUS_CODE) %then %let att_rc = &SYS_PROCHTTP_STATUS_CODE;

    data _rr_att_names;
        length name $512;
        stop;
    run;
    %if &att_rc = 200 %then %do;
        libname _rratt json fileref=_rratt;
        %if %sysfunc(libref(_rratt)) = 0 %then %do;
            /* With no attachments, the ITEMS table is missing or has no NAME column - check before reading */
            %let dsid = 0;
            %let has_name = 0;
            %if %sysfunc(exist(_rratt.items)) %then %let dsid = %sysfunc(open(_rratt.items));
            %if &dsid > 0 %then %do;
                %let has_name = %sysfunc(varnum(&dsid, name));
                %let rc = %sysfunc(close(&dsid));
            %end;

            %if &has_name > 0 %then %do;
                data _rr_att_names;
                    length name $512;
                    set _rratt.items(keep=name);
                run;
            %end;
            %else %put NOTE: No attachments on report &report_id - this export is V1.;
            libname _rratt clear;
        %end;
    %end;
    %else %put WARNING: Could not read the report attachments (HTTP &att_rc) - version set to V1.;
    filename _rratt clear;

    proc sql noprint;
        select count(*),
               coalesce(max(case when prxmatch('/_V\d+\.xml$/i', strip(name))
                                 then input(prxchange('s/^.*_V(\d+)\.xml$/$1/i', 1, strip(name)), 8.)
                                 else 0 end), 0)
          into :xml_count trimmed, :max_ver trimmed
        from _rr_att_names
        where prxmatch('/\.xml$/i', strip(name)) > 0;
    quit;
    %put NOTE: XML attachments on report = &xml_count, highest version used = V&max_ver;

    data _null_;
        length reportpart type casepart userraw userpart newname $256;

        /* Keep each part file-name safe: characters not allowed in file names and spaces become _ */
        if lowcase(strip(symget('goaml_name_report_part'))) = 'year'
            then reportpart = scan(strip(symget('report_id')), 1, '_');    /* RR2026 */
            else reportpart = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(symget('report_id')));   /* RR2026_100047 */
        type     = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(symget('report_type')));
        casepart = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(symget('case_id')));
        userraw  = strip(symget('export_user'));
        if userraw = '' then userraw = strip(symget('current_user'));
        userpart = prxchange('s/[\\\/:*?"<>|\s]+/_/', -1, strip(userraw));
        if casepart = '' then casepart = 'NOCASE';
        if userpart = '' then userpart = 'NOUSER';

        /* This export's version: one more than the XML files already attached,
           and never lower than the highest V# already used + 1 */
        version = max(input(symget('xml_count'), 8.), input(symget('max_ver'), 8.)) + 1;

        newname = cats(catx('_', type, casepart, reportpart, userpart, cats('V', version)), '.xml');
        call symputx('fileName', newname, 'G');
        put 'NOTE: XML name for attachment and download: ' newname;
    run;

    %put NOTE: xmlPath=&xmlPath;
    %put NOTE: fileName=&fileName;
%mend goaml_xml_name;

%goaml_xml_name;
%goaml_timer(file name - user and attachment lookups);




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

filename upFileN "&xmlPath";   /* saved file on disk; it is named &fileName in SVI */
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
%FileAttribs(&xmlPath);
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
%goaml_timer(upload to File Service);






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
%goaml_timer(attach to report);


/* 7. Return the XML to the browser, named &fileName */
 filename xml "&xmlPath";

%put "&xmlPath";

/* Send the XML as a download named exactly &fileName (e.g. STR_RR2026_202610158_noor.khaled_V1.xml).
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
%goaml_timer(end of job);

