


rm(list=ls())
library(vmstools)
library(maps)
library(mapdata)
memory.size(4000)


# assign an identifier in'HL_ID' to each of the fishing sequences
# (based on SI_STATE, assuming the "h", "f", "s" coding)
# (useful to count them in a grid...)
labellingHauls <- function(tacsat){
            tacsat$SI_STATE2                             <- tacsat$SI_STATE
            tacsat$SI_STATE                              <- as.character(tacsat$SI_STATE)
            tacsat[is.na(tacsat$SI_STATE), 'SI_STATE']   <- '1' # assign steaming
            tacsat[tacsat$SI_STATE!='f', 'SI_STATE']     <- '1' # assign steaming
            tacsat[tacsat$SI_STATE=='f', 'SI_STATE']     <- '2' # assign fishing
            tacsat$SI_STATE                              <- as.numeric(tacsat$SI_STATE)
            tacsat$HL_ID                              <- c(0, diff(tacsat$SI_STATE))   # init
            tacsat$HL_ID                              <- cumsum(tacsat$HL_ID) # fishing sequences detected.
            tacsat$SS_ID                              <- 1- tacsat$HL_ID  # steaming sequences detected.
            tacsat$HL_ID                              <- cumsum(tacsat$SS_ID ) # fishing sequences labelled.
            tacsat[tacsat$SI_STATE==1, 'HL_ID']       <- 0 # correct label 0 for steaming
            tacsat$HL_ID                              <- factor(tacsat$HL_ID)
            levels(tacsat$HL_ID) <- 0: (length(levels(tacsat$HL_ID))-1) # rename the id for increasing numbers from 0
            tacsat$HL_ID                             <- as.character(tacsat$HL_ID)
            # then assign a unique id
            idx <- tacsat$HL_ID!=0
            tacsat[idx, "HL_ID"] <- paste(
                                    tacsat$VE_REF[idx], "_",
                                    tacsat$LE_GEAR[idx], "_",
                                    tacsat$HL_ID[idx],
                                    sep="")
           tacsat$SI_STATE                             <- tacsat$SI_STATE2
           tacsat <- tacsat[, !colnames(tacsat) %in% c('SS_ID', 'SI_STATE2')] # remove useless column
          return(tacsat)

       }

# label fishing sequecnes with a unique identifier (method based on SI_STATE)
#tacsat <- labellingHauls(tacsat)




 if(.Platform$OS.type == "unix") {}
 codePath  <- file.path("~","BENTHIS")
 dataPath  <- file.path("~","BENTHIS","EflaloAndTacsat")
 pricePath <- ""
 outPath   <- file.path("~","BENTHIS", "outputs")
 polPath   <- file.path("~","BENTHIS", "BalanceMaps")
  # do not forget to install the R packages on the qrsh interactive node linux platform, i.e. R > install.packages("data.table"), etc.
  # (and possibly kill the current jobs on HPC with the command qselect -u $USER | xargs qdel)
  # submit the shell to HPC with the command qsub ./benthis_workflow.sh

 if(.Platform$OS.type == "windows") {
 codePath  <- "C:/merging/BENTHIS/"
 dataPath  <- "C:/merging/EflaloAndTacsat/"
 pricePath <- ""
 outPath   <- "C:/merging/BENTHIS/outputs/"
 polPath   <- "C:/merging/BalanceMaps"
 }

 
 a_year <- 2010
 #a_year <- 2011
 #a_year <- 2012
 #a_year <- 2013
 dir.create(file.path(outPath))
 dir.create(file.path(outPath, a_year))
 outPath   <- file.path(outPath, a_year)

if(TRUE){

 # Danish data
 #tacsat <- readTacsat(file.path(dataPath,"tacsat2_2012.csv"))
 #eflalo <- readEflalo(file.path(dataPath,"eflalo3_2012.csv"))
 #save(tacsat, file=file.path(dataPath,"tacsat_2012.RData"))
 #save(eflalo, file=file.path(dataPath,"eflalo_2012.RData"))

 

 load(file.path(dataPath,paste("tacsat_", a_year,".RData", sep=''))); # get the tacsat object
 load(file.path(dataPath,paste("eflalo_", a_year,".RData", sep=''))); # get the eflalo object
 tacsat <- formatTacsat(tacsat) # format each of the columns to the specified class
 eflalo <- formatEflalo(eflalo) # format each of the columns to the specified class

 
 # country-specific
 VMS_ping_rate_in_hour <- 1 # e.g. for Denmark

 
 data(euharbours)
 data(ICESareas)
 data(europa)


 # CLEANING
 remrecsTacsat     <- matrix(NA,nrow=6,ncol=2,dimnames= list(c("total","duplicates","notPossible",
                                                              "pseudoDuplicates","harbour","land"),
                                                            c("rows","percentage")))
 remrecsTacsat["total",] <- c(nrow(tacsat),"100%")

 # Remove duplicate records
 tacsat$SI_DATIM <- as.POSIXct(paste(tacsat$SI_DATE,  tacsat$SI_TIME,   sep=" "),
                              tz="GMT", format="%d/%m/%Y  %H:%M")
 uniqueTacsat    <- paste(tacsat$VE_REF,tacsat$SI_LATI,tacsat$SI_LONG,tacsat$SI_DATIM)
 tacsat          <- tacsat[!duplicated(uniqueTacsat),]
 remrecsTacsat["duplicates",] <- c(nrow(tacsat),100+round((nrow(tacsat) -
                an(remrecsTacsat["total",1]))/an(remrecsTacsat["total",1])*100,2))

 # Remove points that cannot be possible
 spThres         <- 20   #Maximum speed threshold in analyses in nm
 idx           <- which(abs(tacsat$SI_LATI) > 90 | abs(tacsat$SI_LONG) > 180)
 idx           <- unique(c(idx,which(tacsat$SI_HE < 0 | tacsat$SI_HE > 360)))
 idx           <- unique(c(idx,which(tacsat$SI_SP > spThres)))
 if(length(idx)>0) tacsat          <- tacsat[-idx,]
 remrecsTacsat["notPossible",] <- c(nrow(tacsat),100+round((nrow(tacsat) -
                an(remrecsTacsat["total",1]))/an(remrecsTacsat["total",1])*100,2))


 #Remove points which are pseudo duplicates as they have an interval rate < x minutes
 intThres        <- 5    # Minimum difference in time interval in minutes to prevent pseudo duplicates
 tacsat          <- sortTacsat(tacsat)
 tacsatp         <- intervalTacsat(tacsat,level="vessel",fill.na=T)
 tacsat          <- tacsatp[which(tacsatp$INTV > intThres | is.na(tacsatp$INTV)==T),-grep("INTV",colnames(tacsatp))]
 remrecsTacsat["pseudoDuplicates",] <- c(nrow(tacsat),100+round((nrow(tacsat) -
                an(remrecsTacsat["total",1]))/an(remrecsTacsat["total",1])*100,2))

 #  Remove points on land
 pols            <- lonLat2SpatialPolygons(lst=lapply(as.list(sort(unique(europa$SID))),

                        function(x){data.frame(SI_LONG=subset(europa,SID==x)$X,SI_LATI=subset(europa,SID==x)$Y)}))
 idx             <- pointOnLand(tacsat,pols);
 pol             <- tacsat[which(idx == 1),]
 save(pol,file=file.path(outPath,"pointOnLand.RData"))
 tacsat          <- tacsat[which(idx == 0),]
 remrecsTacsat["land",] <- c(nrow(tacsat),100+round((nrow(tacsat) -
                an(remrecsTacsat["total",1]))/an(remrecsTacsat["total",1])*100,2))


 # Save the remrecsTacsat file
 save(remrecsTacsat,file=file.path(outPath,"remrecsTacsat.RData"))
 
 # Save the cleaned tacsat file
 save(tacsat,file=file.path(outPath,"cleanTacsat.RData"))

 
 # CLEANING EFLALO

 # Keep track of removed points
 remrecsEflalo     <- matrix(NA,nrow=5,ncol=2,dimnames=list(c("total","duplicated","impossible time",
                                                             "before 1st Jan","departArrival"),
                                                           c("rows","percentage")))
 remrecsEflalo["total",] <- c(nrow(eflalo),"100%")

 # Remove non-unique trip numbers
 eflalo            <- eflalo[!duplicated(paste(eflalo$LE_ID,eflalo$LE_CDAT,sep="-")),]
 remrecsEflalo["duplicated",] <- c(nrow(eflalo),100+round((nrow(eflalo) -
                  an(remrecsEflalo["total",1]))/an(remrecsEflalo["total",1])*100,2))

 # Remove impossible time stamp records
 eflalo$FT_DDATIM  <- as.POSIXct(paste(eflalo$FT_DDAT,eflalo$FT_DTIME, sep = " "),
                               tz = "GMT", format = "%d/%m/%Y  %H:%M")
 eflalo$FT_LDATIM  <- as.POSIXct(paste(eflalo$FT_LDAT,eflalo$FT_LTIME, sep = " "),
                               tz = "GMT", format = "%d/%m/%Y  %H:%M")

 eflalo            <- eflalo[!(is.na(eflalo$FT_DDATIM) |is.na(eflalo$FT_LDATIM)),]
 remrecsEflalo["impossible time",] <- c(nrow(eflalo),100+round((nrow(eflalo) -
                  an(remrecsEflalo["total",1]))/an(remrecsEflalo["total",1])*100,2))

 # Remove trip starting befor 1st Jan
 year              <- min(year(eflalo$FT_DDATIM))
 eflalo            <- eflalo[eflalo$FT_DDATIM>=strptime(paste(year,"-01-01 00:00:00",sep=''),
                                                             "%Y-%m-%d %H:%M:%S"),]
 remrecsEflalo["before 1st Jan",] <- c(nrow(eflalo),100+round((nrow(eflalo) -
                  an(remrecsEflalo["total",1]))/an(remrecsEflalo["total",1])*100,2))

 # Remove records with arrival date before departure date
 eflalop           <- eflalo
 eflalop$FT_DDATIM <- as.POSIXct(paste(eflalo$FT_DDAT,  eflalo$FT_DTIME,   sep=" "),
                                tz="GMT", format="%d/%m/%Y  %H:%M")
 eflalop$FT_LDATIM <- as.POSIXct(paste(eflalo$FT_LDAT,  eflalo$FT_LTIME,   sep=" "),
                                tz="GMT", format="%d/%m/%Y  %H:%M")
 idx               <- which(eflalop$FT_LDATIM >= eflalop$FT_DDATIM)
 eflalo            <- eflalo[idx,]
 remrecsEflalo["departArrival",] <- c(nrow(eflalo),100+round((nrow(eflalo) -
                  an(remrecsEflalo["total",1]))/an(remrecsEflalo["total",1])*100,2))

 # Save the remrecsEflalo file
 save(remrecsEflalo,file=file.path(outPath,"remrecsEflalo.RData"))

 # Save the cleaned eflalo file
 save(eflalo,file=file.path(outPath,"cleanEflalo.RData"))


 # effort < 15m vs >15m
 # TO DO....
  eflalo$length_class <- cut(as.numeric(as.character(eflalo$VE_LEN)), breaks=c(0,15,100))   #DCF but VMS!
 # compute effort
   eflalo$SI_DATIM     <- as.POSIXct(paste(eflalo$FT_DDAT,  eflalo$FT_DTIME,   sep=" "), tz="GMT", format="%d/%m/%Y  %H:%M")
   eflalo              <- subset(eflalo,FT_REF != 0)
   eflalo$ID           <- paste(eflalo$VE_REF, eflalo$FT_REF,sep="_")
   library(doBy)
   eflalo              <- orderBy(~VE_REF+SI_DATIM+FT_REF, data=eflalo)
   eflalo$SI_DATIM2    <- as.POSIXct(paste(eflalo$FT_LDAT,  eflalo$FT_LTIME,    sep=" "), tz="GMT", format="%d/%m/%Y  %H:%M")
   an                  <- function(x) as.numeric(as.character(x))
   eflalo$LE_EFF       <- an(difftime(eflalo$SI_DATIM2, eflalo$SI_DATIM, units="hours"))
   ef <- eflalo[eflalo$LE_GEAR %in% c('OTB', 'TBB', 'PTB', 'PTM', 'DRB'),]  # TO DO: list to be checked
   aggregate(ef$LE_EFF, list(ef$length_class), sum)


  gc(reset=TRUE)

 # MERGING
 tacsatp           <- mergeEflalo2Tacsat(eflalo,tacsat)

 tacsatp$LE_GEAR   <- eflalo$LE_GEAR[match(tacsatp$FT_REF,eflalo$FT_REF)]
 tacsatp$VE_LEN    <- eflalo$VE_LEN[ match(tacsatp$FT_REF,eflalo$FT_REF)]
 tacsatp$LE_MET    <- eflalo$LE_MET[ match(tacsatp$FT_REF,eflalo$FT_REF)]
 tacsatp$VE_KW     <- eflalo$VE_KW[ match(tacsatp$FT_REF,eflalo$FT_REF)]
 save(tacsatp,   file=file.path(outPath,"tacsatMerged.RData"))

 
 
 # MERGE WITH GEAR WIDTH
 #vesselGear            <- tacsatp[!duplicated(data.frame(tacsatp$VE_REF,tacsatp$LE_GEAR)), ]
 #fakeGearWidth         <- vesselGear[,c('VE_REF', 'LE_GEAR')]
 #fakeGearWidth         <- fakeGearWidth[-which(is.na(fakeGearWidth$VE_REF) | is.na(fakeGearWidth$LE_GEAR)),]
 #fakeGearWidth$LE_GEAR_WIDTH <- 0.5 # in km
 #save(fakeGearWidth, file=file.path(dataPath,"gearWidth.RData"))
 #load(file.path(dataPath, "gearWidth.RData"))
 #tacsatp               <- merge(tacsatp, fakeGearWidth,by=c("VE_REF","LE_GEAR"),
 #                              all.x=T,all.y=F)

 # MERGE WITH GEAR WIDTH
 # CAUTION: the LE_MET should be consistent with those described in the below table!
 # if not then redefine them BEFORE making this step!
 # import the param table obtained from the industry_data R analyses
 gear_param_per_metier       <- read.table(file=file.path(outPath, "estimates_for_gear_param_per_metier.txt"))

 GearWidth                   <- tacsatp[!duplicated(data.frame(tacsatp$VE_REF,tacsatp$LE_MET)), ]
 GearWidth                   <- GearWidth[,c('VE_REF','LE_MET','VE_KW', 'VE_LEN') ]
 GearWidth$GEAR_WIDTH        <- NA
 GearWidth$GEAR_WIDTH_LOWER  <- NA
 GearWidth$GEAR_WIDTH_UPPER  <- NA
 for (i in 1:nrow(GearWidth)) { # brute force...
    kW      <- GearWidth$VE_KW[i]
    LOA     <- GearWidth$VE_LEN[i]
    this    <- gear_param_per_metier[gear_param_per_metier$a_metier==GearWidth$LE_MET[i],]
    a <- NULL ; b <- NULL
    a       <- this[this$param=='a', 'Estimate'] 
    b       <- this[this$param=='b', 'Estimate'] 
    GearWidth[i,"GEAR_WIDTH"]  <-   eval(parse(text= as.character(this[1, 'equ']))) / 1000 # converted in km
    a       <- this[this$param=='a', 'Estimate'] +2*this[this$param=='a', 'Std..Error'] 
    b       <- this[this$param=='b', 'Estimate'] +2*this[this$param=='b', 'Std..Error'] 
    GearWidth[i,"GEAR_WIDTH_UPPER"]  <-  eval(parse(text= as.character(this[1, 'equ']))) / 1000 # converted in km
    a       <- this[this$param=='a', 'Estimate'] -2*this[this$param=='a', 'Std..Error'] 
    b       <- this[this$param=='b', 'Estimate'] -2*this[this$param=='b', 'Std..Error'] 
    GearWidth[i,"GEAR_WIDTH_LOWER"]  <-  eval(parse(text= as.character(this[1, 'equ']))) / 1000 # converted in km  
 }
 save(GearWidth, file=file.path(dataPath,"gearWidth.RData"))
 load(file.path(dataPath, "gearWidth.RData"))
 tacsatp                     <- merge(tacsatp, GearWidth,by=c("VE_REF","LE_MET"),
                               all.x=T,all.y=F)
 save(tacsatp,   file=file.path(outPath,"tacsatMergedWidth.RData"))


 # Save not merged tacsat data
 tacsatpmin        <- subset(tacsatp,FT_REF == 0)
 save(tacsatpmin, file=file.path(outPath,"tacsatNotMerged.RData"))


 # DEFINE ACTIVITIES
 idx               <- which(is.na(tacsatp$VE_REF) == T   | is.na(tacsatp$SI_LONG) == T | is.na(tacsatp$SI_LATI) == T |
                               is.na(tacsatp$SI_DATIM) == T |  is.na(tacsatp$SI_SP) == T)
 if(length(idx)>0) tacsatp         <- tacsatp[-idx,]
 
 
 
 if(.Platform$OS.type == "windows" & TRUE) {
    storeScheme       <- activityTacsatAnalyse(tacsatp, units = "year", analyse.by = "LE_GEAR",identify="means")
    storeScheme       <- storeScheme[-which(is.na(storeScheme$analyse.by)==T),]

    storeScheme       <- storeScheme[storeScheme$years==a_year,]
    storeScheme$years <- as.numeric(as.character(storeScheme$years))
    # debug storeScheme
    for (i in 1:nrow(storeScheme)) storeScheme[i, "means"] <-  paste(strsplit(storeScheme[i,"means"], " ")[[1]][-1], collapse=" ")  # debug : remove a useless buggy white space in 'means'
    save(storeScheme, file=file.path(outPath, "storeScheme.RData"))
    }
    # else... assumed to be already informed for unix
 






  library(vmstools)
  load(file.path(outPath, "tacsatMergedWidth.RData"))
  load(file.path(outPath, "storeScheme.RData"))

  tacsatp$year      <- format(tacsatp$SI_DATIM, "%Y")
  tacsatp           <- tacsatp[tacsatp$year %in% a_year,]

  activity          <- activityTacsat(tacsatp,units="year",analyse.by="LE_GEAR",storeScheme,
                                plot=FALSE, level="all")
 tacsatp$SI_STATE  <- NA
 tacsatp$SI_STATE  <- activity

 idx               <- which(is.na(tacsatp$SI_STATE))
 tacsatp$SI_STATE[idx[which(tacsatp$SI_SP[idx] >= 1.5 &
                           tacsatp$SI_SP[idx] <= 7.5)]] <- 'f'
 tacsatp$SI_STATE[idx[which(tacsatp$SI_SP[idx] <  1.5)]] <- 'h'
 tacsatp$SI_STATE[idx[which(tacsatp$SI_SP[idx] >  7.5)]] <- 's'

 save(tacsatp,     file=file.path(outPath,"tacsatActivity.RData"))









 load(file=file.path(outPath,"tacsatActivity.RData"))


 # Labelling each haul (caution: to do before discarding the steaming points...)
 tacsatp   <- labellingHauls(tacsatp)    ## NOT IN THE namespace of VMSTOOLS??




 # INTERPOLATION (OF THE FISHING SEQUENCES ONLY)
 dir.create(file.path(outPath, "interpolated"))
 towed_gears       <- c('OTB', 'TBB', 'PTB', 'PTM', 'DRB') 
 tacsatp           <- orderBy(~VE_REF+SI_DATIM,data=tacsatp)

 # KEEP ONLY fish. seq. bounded by steaming points
 tacsatp$SI_STATE_num <- NA
 tacsatp$SI_STATE_num[which(tacsatp$SI_STATE=="h")] <- 1
 tacsatp$SI_STATE_num[tacsatp$SI_STATE=="f"] <- 2
 tacsatp$SI_STATE_num[tacsatp$SI_STATE=="s"] <- 3
 is_transition     <- c(0,diff(tacsatp$SI_STATE_num))
 is_transition2    <- c(diff(tacsatp$SI_STATE_num), 0)
 tacsatp           <- tacsatp[ !is.na(tacsatp$SI_STATE_num) & (tacsatp$SI_STATE_num ==2 |
                                      is_transition!=0 | is_transition2!=0),]
 tacsatp           <- tacsatp[,-grep("SI_STATE_num",colnames(tacsatp))]
 tacsatp$SI_STATE  <- "f"


 # per gear per vessel
 for(iGr in towed_gears){
  tacsatpGear        <- tacsatp[!is.na(tacsatp$LE_GEAR) & tacsatp$LE_GEAR==iGr,]

    for(iVE_REF in sort(unique(tacsatpGear$VE_REF))){
    tacsatpGearVEREF <- tacsatpGear[tacsatpGear$VE_REF %in% iVE_REF,]
    if(nrow(tacsatpGearVEREF)>3) {

          cat(paste(iGr, " ", iVE_REF, "\n"))

         #Interpolate according to the cubic-hermite spline interpolation
          interpolationcHs <- interpolateTacsat(tacsatpGearVEREF,
                            interval=VMS_ping_rate_in_hour*60, ## THE PING RATE IS COUNTRY-SPECIFIC ##
                            margin=10, # i.e. will make disconnected interpolations if interval out of the 50 70min range
                            res=100,
                            method="cHs",
                            params=list(fm=0.2,distscale=20,sigline=0.2,st=c(2,6)),   # rmenber that st not in use....
                            headingAdjustment=0,
                            fast=FALSE)


             #Make a picture of all interpolations first
          #Get the ranges of the total picture
          if(FALSE){
           ranges <- do.call(rbind,lapply(interpolationcHs,function(x){return(apply(x[-1,],2,range))}))
           xrange <- range(ranges[,"x"])
           yrange <- range(ranges[,"y"])

           plot(tacsatpGearVEREF$SI_LONG, tacsatpGearVEREF$SI_LATI,
                  xlim=xrange,ylim=yrange,pch=19,col="blue",xlab="Longitude",ylab="Latitude")
           for(iInt in 1:length(interpolationcHs)){
           lines(interpolationcHs[[iInt]][-1,1],interpolationcHs[[iInt]][-1,2])}
           }

         #- Convert the interpolation to tacsat style data
         tacsatpGearVEREF$SI_TIME <- as.character(tacsatpGearVEREF$SI_TIME) #debug
         tacsatIntGearVEREF <- interpolation2Tacsat(interpolationcHs, tacsatpGearVEREF)


         #- Correct for HL_ID skipping
         #tacsatIntGearVEREF$HL_ID[which(diff(as.numeric(tacsatIntGearVEREF$HL_ID))<0)] <- tacsatIntGearVEREF$HL_ID[(which(diff(as.numeric(tacsatIntGearVEREF$HL_ID))<0)-1)]

        #  the swept area (note that could work oustide the loop area as well....)
         tacsatIntGearVEREF$SWEPT_AREA_KM2 <- NA
         a_dist <- distance(c(tacsatIntGearVEREF$SI_LONG[-1],0),  c(tacsatIntGearVEREF$SI_LATI[-1],0),
                                                tacsatIntGearVEREF$SI_LONG, tacsatIntGearVEREF$SI_LATI) 
         tacsatIntGearVEREF$SWEPT_AREA_KM2 <- a_dist * tacsatIntGearVEREF$GEAR_WIDTH
         tacsatIntGearVEREF$SWEPT_AREA_KM2_LOWER <- a_dist * tacsatIntGearVEREF$GEAR_WIDTH_LOWER
         tacsatIntGearVEREF$SWEPT_AREA_KM2_UPPER <- a_dist * tacsatIntGearVEREF$GEAR_WIDTH_UPPER

         save(tacsatIntGearVEREF, file=file.path(outPath, "interpolated",
          paste("tacsatSweptArea_",iVE_REF, "_", iGr, ".RData", sep="")))
         }
       }
    }


 # for seiners 
  all_gears            <- sort(unique(tacsatp$LE_GEAR))
  seine_gears          <- c('SDN', 'SSC') 

  for(iGr in seine_gears){

    tacsatpGear        <- tacsatp[!is.na(tacsatp$LE_GEAR) & tacsatp$LE_GEAR==iGr,]

    for(iVE_REF in sort(unique(tacsatpGear$VE_REF))){
      cat(paste(iGr, " ", iVE_REF, "\n"))
      tacsatpGearVEREF <- tacsatpGear[tacsatpGear$VE_REF %in% iVE_REF,]
      tacsatpGearVEREF <- tacsatpGearVEREF[tacsatpGearVEREF$SI_STATE=='f',] # keep fishing pings only


    tacsatpGearVEREF$SWEPT_AREA_KM2         <- pi*(tacsatpGearVEREF$GEAR_WIDTH/(2*pi))^2
    tacsatpGearVEREF$SWEPT_AREA_KM2_LOWER   <- pi*(tacsatpGearVEREF$GEAR_WIDTH_LOWER/(2*pi))^2
    tacsatpGearVEREF$SWEPT_AREA_KM2_UPPER   <- pi*(tacsatpGearVEREF$GEAR_WIDTH_UPPER/(2*pi))^2

    haul_duration                           <- 3 # assumption of a mean duration based from questionnaires to seiners
    tacsatpGearVEREF$SWEPT_AREA_KM2         <- tacsatpGearVEREF$SWEPT_AREA_KM2 * VMS_ping_rate_in_hour / haul_duration # correction to avoid counting the same circle are several time.
    tacsatpGearVEREF$SWEPT_AREA_KM2_LOWER         <- tacsatpGearVEREF$SWEPT_AREA_KM2_LOWER * VMS_ping_rate_in_hour / haul_duration # correction to avoid counting the same circle are several time.
    tacsatpGearVEREF$SWEPT_AREA_KM2_UPPER         <- tacsatpGearVEREF$SWEPT_AREA_KM2_UPPER * VMS_ping_rate_in_hour / haul_duration # correction to avoid counting the same circle are several time.
    idx                                     <- grep('SSC', as.character(tacsatpGearVEREF$LE_GEAR))
    tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2'] <- tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2'] *1.5 # ad hoc correction to account for the SSC specificities
    tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2_LOWER'] <- tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2_LOWER'] *1.5 # ad hoc correction to account for the SSC specificities
    tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2_UPPER'] <- tacsatpGearVEREF[idx, 'SWEPT_AREA_KM2_UPPER'] *1.5 # ad hoc correction to account for the SSC specificities

    tacsatIntGearVEREF <- tacsatpGearVEREF
     
    save(tacsatIntGearVEREF, file=file.path(outPath, "interpolated",
       paste("tacsatSweptArea_",iVE_REF, "_", iGr, ".RData", sep="")))
  }
 }
 
 
 
 
 } # end TRUE/FALSE

 
  # SWEPT AREA DATASET
  # after having subsetted per gear per vessel (because risk of 'out of memory')
    lst <- list(NULL) ; count <- 0
    for(iGr in unique(tacsatp$LE_GEAR)){
      tacsatpGear        <- tacsatp[!is.na(tacsatp$LE_GEAR) & tacsatp$LE_GEAR==iGr,]

         for(iVE_REF in sort(unique(tacsatpGear$VE_REF))){

          cat(paste(iGr, " ", iVE_REF, "\n"))

          count <- count+1

          cat(paste("load ", iVE_REF, " and ", iGr, "\n", sep=""))
          er <- try(load(file.path(outPath, "interpolated",
                paste("tacsatSweptArea_",iVE_REF, "_", iGr, ".RData", sep=""))),
                silent=TRUE)
          if(class(er)=="try-error"){
          count <- count -1
          } else{
          lst[[count]] <-  tacsatIntGearVEREF
          }

      }

    }
    tacsatp <- do.call("rbind", lst)

    # save
    save(tacsatp, file=file.path(outPath, paste("tacsatSweptArea.RData", sep="")))
    
    
    

# compute (discrete point) effort_days and effort_KWdays
 #......
  library(doBy)
  tacsatp                  <- orderBy(~VE_REF+SI_DATIM+FT_REF,data=tacsatp)
  tacsatp$effort_days      <- as.numeric(as.character(difftime(c(tacsatp$SI_DATIM[-1],0),tacsatp$SI_DATIM,units="days")))
  tacsatp$effort_KWdays    <- tacsatp$effort_days *  as.numeric(as.character(tacsatp$VE_KW))
  #tacsatp$effort_days   [which(diff(as.numeric(tacsatp$HL_ID))<0)]     <- 0  # correct (to do: but pble of steaming pts which have been converted to fish. pts)
  #tacsatp$effort_KWdays [which(diff(as.numeric(tacsatp$HL_ID))<0)]     <- 0  # correct
  ## for the time being, do:
  tacsatp$effort_days[tacsatp$effort_days>0.014] <- 0  # correct (i.e. set at 0 if >3hours as a sign for a change of haul)


 
 
 
  ## LINK TO HABITAT MAPS
  ##
  # SHAPEFILE--------
  library(maptools)

  # load a habitat map shape file
  habitat_map           <- readShapePoly(file.path(polPath,"sediment_lat_long"),
                                         proj4string=CRS("+proj=longlat +ellps=WGS84"))

  sh_coastlines            <- readShapePoly(file.path(polPath,"francois_EU"))


  load(file.path(outPath, "tacsatSweptArea.RData")) # get 'tacsatp' with all data
  #....or load only one instance eg load(file.path(outPath, "interpolated","tacsatSweptArea_DNK000005269_OTB.RData"))
  #tacsatp <- tacsatInt_gr_vid

  coord <-  tacsatp[, c('SI_LONG', 'SI_LATI')]
  names(habitat_map) # return the name of the coding variable

  #Turn the polygons into spatial polygons
  sp <- SpatialPolygons(habitat_map@polygons)
  projection(sp) <-  CRS("+proj=longlat +ellps=WGS84")

  #Turn the point into a spatial point
  spo <- SpatialPoints(coordinates(data.frame(SI_LONG=coord[,1],
                                             SI_LATI=coord[,2])))
  projection(spo) <-  CRS("+proj=longlat +ellps=WGS84")

  #Use the magic 'over' function to see in which polygon it is located
  idx <- over(spo,sp); print(idx)
  tacsatp$SUBSTRATE <- habitat_map$BAL_CODE[idx]

  # plot
  plot(habitat_map, xlim=c(11,14), ylim=c(55,56))
  axis(1) ; axis(2, las=2) ; box()
  points(tacsatp[, c("SI_LONG","SI_LATI")], col=tacsatp$SUBSTRATE, pch=".")
  #plot(sh_coastlines, add=TRUE)

  # save
  savePlot(filename=file.path(outPath, "VMSpingsAttachedToSedimentMap.jpeg"), type="jpeg")

     
  # RASTER--------
  sh_coastlines            <- readShapePoly(file.path(polPath,"francois_EU"))

  ## use point-raster overlay.......
  library(raster)
  landscapes       <- raster(file.path(polPath, "landscapes.tif"))    # probably need an update of rgdal here....
  newproj          <- "+proj=longlat +datum=WGS84"
  landscapes_proj  <- projectRaster(landscapes, crs=newproj)

  save(landscapes_proj, file=file.path(polPath, "landscapes_proj.RData"))

  load(file.path(polPath, "landscapes_proj.RData"))

  load(file.path(outPath, "tacsatSweptArea.RData")) # get 'tacsatp' with all data
  #....or load only one instance eg load("C:\\merging\\BENTHIS\\outputs\\interpolated\\tacsatSweptArea_DNK000005269_OTB.RData"))
  #tacsatp <- tacsatpGearVEREF


  coord <- cbind(x=anf(tacsatp$SI_LONG), y=anf(tacsatp$SI_LATI))

  dd <- extract (landscapes_proj, coord[,1:2]) # get the landscape on the coord points!

  coord <- cbind(coord,  landscapes_code=cut(dd, breaks=c(0,100,200,300,400,500,600)))

  tacsatp <- cbind(tacsatp, landscapes_code= coord[,'landscapes_code'])

  # plot and save...
  plot(landscapes_proj, xlim=c(10,14), ylim=c(54.5,56.5))
  plot(sh_coastlines,  xlim=c(10,14), ylim=c(54.5,56.5), add=TRUE)  # better for plotting the western baltic sea coastline!
  points(coord[,"x"], coord[,"y"], col=coord[,"landscapes_code"], pch=".", cex=1)

  # save
  savePlot(filename=file.path(outPath, "VMSpingsAttachedToLandscapeMap.jpeg"), type="jpeg")











  # SEVERITY OF IMPACT
  # create a fake input file to show the required format
  dd <- tacsatp[!duplicated(data.frame(tacsatp$VE_REF,tacsatp$LE_GEAR, tacsatp$LE_MET)), ]
  fake_gear_metier_habitat_severity_table <- dd[,c('VE_REF', 'LE_GEAR', 'LE_MET')]
  fake_gear_metier_habitat_severity_table <- cbind(fake_gear_metier_habitat_severity_table, HAB_SEVERITY=1)
  gear_metier_habitat_severity_table  <- fake_gear_metier_habitat_severity_table
  gear_metier_habitat_severity_table  <-   gear_metier_habitat_severity_table[complete.cases( gear_metier_habitat_severity_table),]
  save(gear_metier_habitat_severity_table,   file=paste(dataPath,"gear_metier_habitat_severity_table.RData",   sep=""))

  # load a table for HAB_SEVERITY per vid LE_REF per gr LE_GEAR per met LE_MET
  load(file.path(dataPath, "gear_metier_habitat_severity_table.RData"))
  tacsatp <- merge(tacsatp, gear_metier_habitat_severity_table)
  save(tacsatp,   file=paste(outPath,"tacsatMergedHabSeverity.RData",   sep=""))

  # pressure: weigh the swept area by the severity
  tacsatp$pressure <- tacsatp$HAB_SEVERITY * tacsatp$SWEPT_AREA_KM2















  ## GRIDDING (IN DECIMAL DEGREES OR UTM COORD)
  # using a quick gridding code at various resolution.

  # For example, grid the swept area, or the number of hauls, or the fishing pressure, etc.
  sh1 <- readShapePoly(file.path(polPath,"francois_EU"))



  ### the swept area-------------------------------------------

   ## user selection here----
    what                 <- "SWEPT_AREA_KM2"
    #what                <- "HL_ID"
    #what                <- "effort_days"
    #what                <- "effort_KWdays"
    #what                <- "pressure"
    #a_func              <- function(x) {unique(length(x))} # for HL_ID, to be tested.
    a_func               <- "sum"
    is_utm               <- FALSE
    all_gears            <- sort(unique(tacsatp$LE_GEAR))
    towed_gears          <- c('OTB', 'TBB', 'PTB', 'PTM', 'DRB')  # TO DO: list to be checked
    passive_gears        <- all_gears[!all_gears %in% towed_gears]
    ##------------------------

    # subset for relevant fisheries
    this            <- tacsatp [tacsatp$LE_GEAR %in% towed_gears , ]

    # restrict the study area
    we <- 10; ea <- 13; no <- 59; so <- 55;
    this <- this[this$SI_LONG>we & this$SI_LONG<ea & this$SI_LATI>so & this$SI_LATI<no,]

    # grid the data (in decimal or in UTM)
    if(is_utm){
      dx <- 0.0002 # 5km x 5km
      # convert to UTM
      library(sp)
      library(rgdal)
      SP <- SpatialPoints(cbind(as.numeric(as.character(this$SI_LONG)), as.numeric(as.character(this$SI_LATI))),
                       proj4string=CRS("+proj=longlat +datum=WGS84"))
      this <- cbind(this,
                 spTransform(SP, CRS("+proj=utm  +ellps=intl +zone=32 +towgs84=-84,-107,-120,0,0,0,0,0")))    # convert to UTM
      this            <- this [, c('SI_LONG', 'SI_LATI', 'SI_DATE', 'coords.x1', 'coords.x2', what)]
      this$round_long <- round(as.numeric(as.character(this$coords.x1))*dx*2)
      this$round_lat  <- round(as.numeric(as.character(this$coords.x2))*dx)
      this            <- this[, !colnames(this) %in% c('coords.x1', 'coords.x2')]
    }  else {
      dx <- 20
      this <- this [, c('SI_LONG', 'SI_LATI', 'SI_DATE', what)]
      this$round_long <- round(as.numeric(as.character(this$SI_LONG))*dx*2)
      this$round_lat  <- round(as.numeric(as.character(this$SI_LATI))*dx)
    }
     # if the coordinates in decimal then dx=20 corresponds to grid resolution of 0.05 degrees
     # i.e. a 3� angle = 3nm in latitude but vary in longitude (note that a finer grid will be produced if a higher value for dx is put here)
     # if coord in UTM then 0.001 correspond to grid of 1 by 1 km (to check)

    this$cell       <- paste("C_",this$round_long,"_", this$round_lat, sep='')
    this$xs         <- (this$round_long/(dx*2))
    this$ys         <- (this$round_lat/(dx))
    colnames(this) <- c('x', 'y', 'date', 'what', 'round_long', 'round_lat', 'cell', 'xs', 'ys')


    # retrieve the geo resolution in degree, for info
    #long <- seq(1,15,by=0.01)
    #res_long <- diff( long [1+which(diff(round(long*dx)/dx/2)!=0)] )
    #res_lat <- diff( long [1+which(diff(round(long*dx/2)/dx)!=0)] )
    #print(res_long) ; print(res_lat)


    # a quick gridding method...
    background <- expand.grid(
                              x=0,
                              y=0,
                              date=0,
                              what=0,
                              round_long=seq(range(this$round_long)[1], range(this$round_long)[2], by=1),
                              round_lat=seq(range(this$round_lat)[1], range(this$round_lat)[2], by=1),
                              cell=0,
                              xs=0,
                              ys=0
                              )
    this <- rbind(this, background)
    the_points <- tapply(this$what,
                  list(this$round_lat, this$round_long), a_func)

    xs <- (as.numeric(as.character(colnames(the_points)))/(dx*2))
    ys <- (as.numeric(as.character(rownames(the_points)))/(dx))

    the_breaks <-  c(0, (1:12)^3.5 )
    graphics:::image(
     x=xs,
     y=ys,
     z= t(the_points)  ,
     breaks=c(the_breaks),
     col = terrain.colors(length(the_breaks)-1),
     useRaster=FALSE,
     xlab="",
     ylab="",
     axes=FALSE,
     xlim=range(xs), ylim=range(ys),
     add=FALSE
     )
    title("")

    # land
    sh1 <- readShapePoly(file.path(polPath,"francois_EU"),  proj4string=CRS("+proj=longlat +datum=WGS84"))
    if(is_utm) sh1 <- spTransform(sh1, CRS("+proj=utm  +ellps=intl +zone=32 +towgs84=-84,-107,-120,0,0,0,0,0"))
    plot(sh1, add=TRUE, col=grey(0.7))

    legend("topright", fill=terrain.colors(length(the_breaks)-1),
             legend=round(the_breaks[-1],1), bty="n", cex=0.8, ncol=2, title="")
    box()
    axis(1)
    axis(2, las=2)

    if(is_utm){
      mtext(side=1, "Eastings", cex=1, adj=0.5, line=2)
      mtext(side=2, "Northings", cex=1, adj=0.5, line=2)
    } else{
      mtext(side=1, "Longitude", cex=1, adj=0.5, line=2)
      mtext(side=2, "Latitude", cex=1, adj=0.5, line=2)
      #points (tacsatp [,c('SI_LONG', 'SI_LATI')], pch=".", col="white")
    }
    
    
    # save
    savePlot(filename=file.path(outPath, "GriddedSweepAreaExample.jpeg"), type="jpeg")


    # export the quantity per cell and date
    library(data.table)
    DT                <-  data.table(this)
    qu                <-  quote(list(sum(what)))
    quantity_per_cell <- DT[,eval(qu), by=list(cell, xs,ys)]
    quantity_per_date <- DT[,eval(qu), by=list(date, xs,ys)]
    quantity_per_cell_date <- DT[,eval(qu), by=list(cell,date, xs,ys)]
    quantity_per_cell_date <- as.data.frame(quantity_per_cell_date)
    colnames(quantity_per_cell_date)   <- c('cell','date', 'xs','ys', 'quantity')
    rm(DT) ; gc(reset=TRUE)
    save(quantity_per_cell_date, res_long, res_lat,  we, ea, no, so, file=file.path(outPath,"quantity_per_cell_date.RData") )


    # export the cumul per cell and date
    quantity_per_cell_date <- orderBy(~date, data=quantity_per_cell_date)
    quantity_cumul_per_cell_date <- do.call("rbind", lapply(
      split(quantity_per_cell_date, f=quantity_per_cell_date$cell),
               function(x){
               x$quantity <- cumsum(x$quantity)
               x
               })  )
    # check the cumul on a given cell
    # head(quantity_cumul_per_cell_date[quantity_cumul_per_cell_date$cell=="C_197_2722",])
    save(quantity_cumul_per_cell_date, res_long, res_lat,  we, ea, no, so, file=file.path(outPath,"quantity_cumul_per_cell_date.RData") )


               









     