#sap_maxdb_syscopy

#SAP MaxDB System Copy Tool (c) Florian Lamml 2019

#www.florian-lamml.de


Automatic System Copy Tool for SAP Systems in MaxDB and Linux (SLES/RHEL) / Unix (AIX)


Prerequisites 
- ssh communication between source and target without password (authorized_keys(2)) for both sidadm     
  via "ssh-keygen -t rsa -b 2048" and  ".ssh/authorized_keys2" (only source --> target)               
  --> ssh sourceadm@sourcehost must work without PW                                                   
  --> ssh targetadm@targethost must work without PW                                                   
- the target database is large enough (automatic check)                                               
- copy this script to the source host and set the execution right                                     
- xuser DEFAULT for ABAP/JAVA DB User (SAP<SID> or SAP<SID>DB) must be available                      
- if passwords from source and target are different, xuser for copy can not be used                   
- the source database must be online, the target database must be able to start in state admin        
- adjust the configuration of source and target system in this script                                 
- best use with screen tool for unix/linux
- under Linux it can happen that you have to change the first line from "#!/usr/bin/bash" to "#!/bin/bash" (check bash with "which bash")


Features 
- automatic function and prerequisites check                                                          
- backup to 2 parallel PIPE                                                                           
- can use compressed and uncompressed backup (default uncompress)                                     
- root is not needed                                                                                  
- copy status bar with size, transfered, left and speed (5 second update)                             
- automatic size check                                                                                
- dd over ssh from source to target                                                                   
- ssh encryption default cipher is aes192-ctr                                                         
- automatic rename database to target                                                                 
- automatic export of custom tables (incl. templates of the most common)                              
- you can use a custom db user or xuser for backup and restore                                        

