
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
		"Content-Disposition"="attachment; filename=&filePath.&fileName"	
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


 filename xml "&FILEPATH./&fileName"; 

%put "&FILEPATH./&fileName";

data _null_;
    INFILE  xml ;  *recfm=n;
    file _webout  mod lrecl=32760 encoding="utf-8";
    input;
    put _infile_;
run;


/************************************************
* AML - AUTOEXEC.SAS
* Leandro Goncalves / Thomas Frederiksen
* 20/08/2020
************************************************/

options mprint mlogic symbolgen;
/*%include "/nbr/warehouse/default/ucmacros/goaml_autoexec.sas";
%include "&SAS_CUST_ROOT/common/goaml/programs/aml_autoexec.sas";*/
%include "&SAS_CUST_ROOT/ucmacros/xml_special_char.sas";
%include "&SAS_CUST_ROOT/ucmacros/sdk_get_nobs.sas";
%include "&SAS_CUST_ROOT/ucmacros/generateXMLActivities.sas";
%include "&SAS_CUST_ROOT/ucmacros/generateXMLTransactions.sas";
%global xml_file  report_code_id ;

%macro generateXML();
	%let entity_reference=&report_id;
	%let report_id=&entity_reference;
	%let sas_bank_id=10;
	%let proc_sql=noprint;
	%let num_inconsistencies=0;
	%let except_informer=N;
    
	%let SASGoAML_save_path=&SAS_CUST_ROOT;
    %let xml_timestamp=%trim(%sysfunc(date(),yymmddn8.))_%trim(%sysfunc(time(),tod8.));
    /*%let SASGoAML_report_path_rc=%sysfunc(dcreate(&entity_reference. ,&SASGoAML_save_path.));*/
    %put SASGoAML_report_path_rc=&SASGoAML_report_path_rc.;
        %let fileName=&entity_reference._%sysfunc(compress(&xml_timestamp.,':')).xml;
        %let filePath=&SASGoAML_save_path./xml/;
    %let xml_file = "&filePath.&fileName" lrecl=32760 encoding="utf-8";
        %put &=xml_file;
/* 	filename tempXml temp lrecl=32760 encoding="utf-8"; */
/* 	%let xml_file = tempXml;	 */
    %global f d n report_id site_specifics;
    %let f = +(-1); *removing taling space in xml;
    %let d = e8601dt.; *date format for xml;
    %let n = 20.2; *number format for xml;

    /* Site specific parameters */
    %let site_specifics=&SAS_CUST_NAME;
    %let first_nm=Medarbejder userid;
    %let last_nm=&sysuserid;


    %if "&entity_reference." ne "" %then %do;
        proc sql;
            select _ID_NUMERIC_PART_NO
            into :rr_rk
            from sar.rr_report
            where RR_REPORT_ID = "&entity_reference."
            ;
        quit;

        %let cnt_report = 0;
        proc sql noprint;
            select count(rr_report_id) into: cnt_report
                from sar.rr_report
                where RR_REPORT_ID = "&entity_reference."
            ;
        quit;
		%put &cnt_report;

        %if &cnt_report = 1 %then %do;

            /*%checkPerson();
            %checkCompany();
            %checkAccount();
            %checkTransaction();*/

            %if &num_inconsistencies gt 0 %then %do;
                %put NOTE: report missing data;
                /*%outputUserMessageHTML(%str(A valid xml file cannot be generated due to missing values (account, transaction or person).));*/
            %end;
            %else %do;
                /*%get_rentity_id;*/
                %put her er den RPERSON_EMAIL;

                data _null_;
                    file &xml_file.;
                run;
                %let xml_file = &xml_file mod;

				data _null_;
					set sar.rr_settings;
					call symput("rentity_id", compress(rentity_id));
				run;
				data _null_;
					set sar.rr_report(where=(RR_REPORT_ID="&report_id."));
					%xml_special_char(narrative);
					
					call symput("report_code_id", compress(report_code));
				
					call symput("entity_reference_id", compress(entity_reference));

                    	new_date=intnx('hour',datetime(), +4, 'SAME');
		
					call symput("submission_date", put(new_date,&d.));

					%if &site_specifics=&SAS_CUST_NAME %then %do;
						bank_responsible_firstname="&first_nm";
						bank_responsible_lastname="&last_nm";
					%end;
					call symput("report_rentity_id", compress(rentity_id));
					call symput("MLRO_first_name", trim(first_name));
					call symput("MLRO_last_name", trim(last_name));
					call symput("MLRO_number_contact_type", trim(tph_contact_type));
					call symput("MLRO_communication_type", trim(tph_communication_type));
					call symput("MLRO_number", trim(tph_number));
					call symput("MLRO_email", trim(	email));
					
					/*call symput("MLRO_employer_name", trim(bank_name));*/
					call symput("submission_code", trim(submission_code));
					call symput("currency_code_local", trim(currency_code_local));
					/*call symput("reason", trim(narrative));*/
					
					call symput("gender", trim(gender));
					call symput("title_in", trim(title));
				
					call symput("birthdate_in", strip(put(birthdate,&d.)));
						
					call symput("id_number_in", trim(id_number));
					call symput("passport_number_in", trim(passport_number));
					call symput("passport_country_in", trim(passport_country));
					call symput("nationality_in", trim(nationality1));
					
					call symput("phone_cont_type_in", trim(tph_contact_type));
					call symput("phone_comm_type_in", trim(tph_communication_type));
					call symput("phone_prefix_in", trim(tph_country_prefix));
					call symput("tph_extension_in", trim(tph_extension));
					
					call symput("address_type_in", trim(address_type));
					call symput("address_in", trim(address));
					call symput("city_name_in", trim(city));
					call symput("zip_in", trim(zip));
					call symput("country_name_in", trim(country_code));
					call symput("state_name_in", trim(state));
					
					call symput("occupation_in", trim(occupation));
					
					/*reason,and action*/
					length reason $4000.;
					length action $4000.;
					reason = strip(tranwrd(strip(reason),'&','&&amp;'));
reason = strip(tranwrd(strip(reason),'<','&&lt;'));
reason = strip(tranwrd(strip(reason),'>','&&gt;'));
reason = strip(tranwrd(strip(reason),"'","&&apos;"));
reason = strip(tranwrd(strip(reason),'"','&&quot;'));
					
					action=strip(tranwrd(strip(action),'&','&amp;'));
					action=strip(tranwrd(strip(action),'<','&lt;'));
					action=strip(tranwrd(strip(action),'>','&gt;'));
					action=strip(tranwrd(strip(action),"'","&apos;"));
					action=strip(tranwrd(strip(action),'"','&quot;'));
					call symput("reason", trim(reason));
					call symput("action", trim(action));
					
					/*for the location*/
					call symput("branch_address_type", trim(address_type));
					call symput("branch_address", trim(bank_address));
					call symput("branch_city", trim(bank_city));
					call symput("branch_country", trim(bank_country_code));
					call symput("branch_state", trim(bank_state));
					call symput("branch_zip", trim(bank_zip));
					
				run;

                data _null_;
                    file &xml_file.;
                    put '<?xml version="1.0" encoding="UTF-8"?>';
                    put "<report>";
                    put "   <rentity_id>&report_rentity_id.</rentity_id>";
                    put "   <submission_code>&submission_code.</submission_code>";
                    if "&report_code_id." eq "FFR_SAR" or "&report_code_id." eq "FFR_STR"  then do;
						put "   <report_code>FFR</report_code>";
					end;
					else if "&report_code_id." eq "PNMR_SAR" or "&report_code_id." eq "PNMR_STR"  then do;
						put "   <report_code>PNMRA</report_code>";
					end;
					else do;
						put "   <report_code>&report_code_id.</report_code>";
					end;
					
                    put "   <entity_reference>&entity_reference_id.</entity_reference>";
                    put "   <submission_date>&submission_date.</submission_date>";
                    put "   <currency_code_local>&currency_code_local.</currency_code_local>";
                 run;

			     %if &except_informer ne X %then %do;
			                data _null_;
			                file &xml_file.;
			                    put "   <reporting_person>";
								if "&gender" ne " "  and "&gender" ne "-" then do;
									put "       <gender>&gender.</gender>";
								end;
								if "&title_in" ne "" and "&title_in" ne "-"  then do;
									put "       <title>&title_in.</title>";
								end;
			                    put "       <first_name>&MLRO_first_name.</first_name>";
			                    put "       <last_name>&MLRO_last_name.</last_name>";
								if strip("&birthdate_in") ne . then do;
									put "       <birthdate>&birthdate_in.</birthdate>";
								end;
								if "&id_number_in" ne "" then do;
								    put "    <ssn>&id_number_in.</ssn>";
								end;
								if "&passport_number_in" ne "" then do;
									put "       <passport_number>&passport_number_in.</passport_number>";
									if "&passport_country_in" ne "" then do;
									put "       <passport_country>&passport_country_in.</passport_country>";
									end;
								end;
								
								if "&id_number_in" ne "" then do;
									put "       <id_number>&id_number_in.</id_number>";
								end;
								if "&nationality_in" ne "" and "&nationality_in" ne "-"  then do;
									put "       <nationality1>&nationality_in.</nationality1>";
								end;
								if "&phone_cont_type_in" ne "" or "&phone_comm_type_in" ne "" or "&MLRO_number" ne ""  then do;
									put "       <phones>";
									put "           <phone>";
									put "               <tph_contact_type>&phone_cont_type_in.</tph_contact_type>";
									put "               <tph_communication_type>&phone_comm_type_in.</tph_communication_type>";
									if "&phone_prefix_in" ne "" then do;
									  put "               <tph_country_prefix>&phone_prefix_in.</tph_country_prefix>";
									end;
									put "               <tph_number>&MLRO_number.</tph_number>";
									if "&tph_extension_in" ne "" then do;
									  put "               <tph_extension>&tph_extension_in.</tph_extension>";
									end;
									put "           </phone>";
									put "       </phones>";
								end;
								if "&address_type_in" ne "" or "&address_in" ne "" or "&city_name_in" ne ""
								or "&country_name_in" ne "" or "&state_name_in" ne "" 
								then do;
									put "       <addresses>";
									put "           <address>";
									put "               <address_type>&address_type_in.</address_type>";
									put "               <address>&address_in.</address>";
									put "               <city>&city_name_in.</city>";
									if "&zip_in" ne "" then do;
									  put "               <zip>&zip_in.</zip>";
									end;
									put "               <country_code>&country_name_in.</country_code>";
									put "               <state>&state_name_in.</state>";
									put "           </address>";
									put "       </addresses>";
									end;
									if "&MLRO_email" ne "" then do;
										put "       <email>&MLRO_email.</email>";
									end;
									if "&occupation_in" ne "" then do;
										put "       <occupation>&occupation_in.</occupation>";
									end;									
								/*put "       <employer_name>&MLRO_employer_name.</employer_name>";*/
			                    put "   </reporting_person>";
			     %end;

                data _null_;
	                file &xml_file.;
					put "   <location>";
					put "       <address_type>&branch_address_type.</address_type>";
					put "       <address>&branch_address.</address>";
					put "       <city>&branch_city.</city>";
					if "&branch_zip." ne "" then do;
						  put " <zip>&branch_zip.</zip>";
					end;
					put "       <country_code>&branch_country.</country_code>";
					put "       <state>&branch_state.</state>";
					put "   </location>";
					if  "&reason." ne "" then do;
						put "   <reason>&reason.</reason>";
					end;
					if  "&action." ne "" then do;
						put "   <action>&action.</action>";
					end;	
                run;

                %if &report_code_id eq AIF 
				
					or &report_code_id eq HRCA 
				
					or &report_code_id eq ECDD 
					or &report_code_id eq SAR
                    or &report_code_id eq PNMRA
                    or &report_code_id eq CNMRA 
                	or &report_code_id eq CIR
                    or &report_code_id eq  IRR
                    or &report_code_id eq SIR
                    or &report_code_id eq REAR
                    or &report_code_id eq DPMSR
                                    %then %do;
                   %generateXMLActivities();
                %end;
                 %else %if &report_code_id eq AIFT  
 				
					or &report_code_id eq HRC 
				    or &report_code_id eq ITR 
					or &report_code_id eq PSTR 
 				
 					or &report_code_id eq ECDDT 
 					or &report_code_id eq STR	%then %do; 
                  %generateXMLTransactions(); 
             %end; 

                proc sql &proc_sql.;
                    create table indicators as
                        select indicator 
                        from sar.sar_indicator as ind
                        where ind.RR_REPORT_ID="&report_id."
                    ;
                quit;

                %if %sdk_get_nobs(indicators) > 0 %then %do;
                    data _null_;
                        file &xml_file.;
                        put "   <report_indicators>";
                    run;
                    data _null_;
                        file &xml_file.;
                        set indicators;
                        put "           <indicator>" indicator &f. "</indicator>";
                    run;
                    data _null_;
                        file &xml_file.;
                         put "   </report_indicators>";
                    run;
                %end;

                data _null_;
                    file &xml_file.;
                    put "</report>";
                run;

                filename xml &xml_file.;
/*
                /*%let xml_filename_to_save=%scan(%scan(%sysfunc(pathname(xml)),-1,\/),1,' ');
                data _null_;
                    rc = stpsrv_header('Content-type',"Application/xml");
                    rc = stpsrv_header('Content-disposition',"attachment; filename=&xml_filename_to_save.");
                run;

                data _null_;
                    INFILE  xml ;  *recfm=n;
                    file _webout  mod lrecl=32760 encoding="utf-8";
                    input;
                    put _infile_;
                run;
*/
                filename xml clear;
            %end;
        %end;
    %end;
%mend;

%generateXML();

