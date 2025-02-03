# IBMi Backup to S3 / ibmibkp2s3
## Backup your IBM i to IBM Cloud/AWS/GCP/WASABI S3 bucket (Image Catalog)

This project is a working backup BASH script for IBM i. It was tested with IBM i V7R3 and up, but it should work with V7R2 and probably V7R1 too.

The script tries to be modular for better code understanding, but I am not using local but global variables. This could change with future releases.

**I know IBM i BRMS + IBM Cloud Storage Solutions for i can do something similar, with IBM support and at a reasonable price, but you cannot buy the product for withdrawn from marketing OS, you need to pay for the product, not all customers use BRMS, and compression is really slow. ZSTD compression is reasonably fast, and can compress ~4:1 your IBM i cartridges once the backup has been taken.**

##How it works

**The general idea is quite simple:**
* You add "N" Virtual Tape cartridges with "X" size to a Tape Image Catalog. 
* Virtual Tape device is loaded on the Image Catalog
* Backup starts: In this script I take SAVSECDTA, SAVLIB *IBM & SAVLIB *ALLUSR, but you can save anything you want.
* Compress the cartridges using "zstd" command. You can use parallel tasks setting the initial values.
* Upload the data to your S3-compatible object storage bucket. If you are running your IBM i in IBM Power Systems Virtual Server, IBM Cloud Object Storage is a natural choice.
* Uploads can run in parallel jobs, but you can "kill" your HTTP proxy with multipart-uploads and parallel processes. A conservative policy allows to have a (slower) more stable environment. Multipart-uploads are perfect when using direct connection to your bucket.
* You can send an email when job starts and ends. I like to send the backup log, and upload the backup output to the cloud.
* Backups are organized with a PREFIX+YYMMDD format folder. Most object storage solutions allow to expire or move to cheaper storage your old backups, based on rules and policies.

## What's next
**There is a lot of improvement to be done:**
* Needs an automatic restore script, based on command line or parameter file
* Needs a maintenance script to purge old backups (similar to ICC+BRMS)
* Needs a UI and green-screen commands for better IBM i integration.
  

**NOTE:** We already have an IBM i native product, but this script uses a different approach.


