
standardize_OWRS_names <- function(owrs_file, current_class){
  mask <- names(owrs_file$rate_structure[[current_class]]) == "tier_starts_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "tier_starts"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "tier_prices_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "tier_prices"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "flat_rate_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "flat_rate"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "budget_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "budget"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "indoor_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "indoor"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "outdoor_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "outdoor"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "gpcd_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "gpcd"
  
  mask <- names(owrs_file$rate_structure[[current_class]]) == "landscape_factor_commodity"
  names(owrs_file$rate_structure[[current_class]])[mask] <- "landscape_factor"
  
  if(owrs_file$rate_structure[[current_class]]$commodity_charge == "flat_rate_commodity*usage_ccf"){
    owrs_file$rate_structure[[current_class]]$commodity_charge <- "flat_rate*usage_ccf"
  }
  
  owrs_file$rate_structure[[current_class]]$fixed_drought_surcharge <- NULL
  owrs_file$rate_structure[[current_class]]$variable_drought_surcharge <- NULL
  owrs_file$rate_structure[[current_class]]$fixed_wastewater_charge <- NULL
  owrs_file$rate_structure[[current_class]]$variable_wastewater_charge <- NULL
  
  return(owrs_file)
}

singleUtilitySim <- function(df_sample, df_OWRS_row, owrs_file, current_class){

  owrs_file <- standardize_OWRS_names(owrs_file, current_class)
  
  if(owrs_file$rate_structure[[current_class]]$commodity_charge == "flat_rate*usage_ccf"){
    bt <- "Uniform"
  }else {
    bt <- owrs_file$rate_structure[[current_class]]$commodity_charge
  }
  
  if(is.null(owrs_file$metadata$bill_unit)){
    bu <- "ccf"
  }else {
    bu <- owrs_file$metadata$bill_unit
  }
  
  df_temp <- df_sample %>%
    mutate(utility_id = df_OWRS_row$utility_id,
           utility_name = df_OWRS_row$utility_name,
           pwsid = df_OWRS_row$PWSID,
           effective_date = df_OWRS_row$effective_date,
           bill_frequency = owrs_file$metadata$bill_frequency,
           bill_unit = bu,
           bill_type = as.character(bt))
  
  isBimonthly <- length(grep("[Bb][Ii]", df_temp$bill_frequency[1]))
  isAnnual <- length(grep("[Aa][nn]", df_temp$bill_frequency[1]))
  
  # double usage for bimonthly customers
  if(isBimonthly==TRUE){
    df_temp$usage_ccf <- 2*df_temp$usage_ccf
    df_temp$days_in_period <- 2*df_temp$days_in_period
    df_temp$et_amount <- 2*df_temp$et_amount
  }else if(isAnnual){
    df_temp$usage_ccf <- 12*df_temp$usage_ccf
    df_temp$days_in_period <- 12*df_temp$days_in_period
    df_temp$et_amount <- 12*df_temp$et_amount
  }
  
  # Convert units before calculating bills
  if(bu == "kgal"){
    df_temp$usage_ccf <- 0.748*df_temp$usage_ccf
  }
  
  
  #cal bill and validate service charge and commodity charge
  df_temp <- calculate_bill(df_temp, owrs_file)
  df_temp <- hasServiceCharge(df_temp)
  df_temp <- hasCommodityCharge(df_temp)
  
  #for error!!!!!!
  # df_temp <- data.frame(utility, df_NA)
  # df_bill <- rbind(df_bill, df_temp)
  
  # convert back to ccf for filtering and comparison in charts
  if(bu == "kgal"){
    df_temp$usage_ccf <- round(df_temp$usage_ccf/0.748)
  }
  
  # divide bill by two for comparison to monthly customers 
  if(isBimonthly){
    df_temp$usage_ccf <- round(df_temp$usage_ccf/2)
    df_temp$service_charge <- df_temp$service_charge/2.0
    df_temp$commodity_charge <- df_temp$commodity_charge/2.0
    df_temp$bill <- df_temp$bill/2.0
  }else if(isAnnual){
    df_temp$usage_ccf <- round(df_temp$usage_ccf/12)
    df_temp$service_charge <- df_temp$service_charge/12.0
    df_temp$commodity_charge <- df_temp$commodity_charge/12.0
    df_temp$bill <- df_temp$bill/12.0
  }
  
  # calculate percent of bill that comes from fixed charges
  percentFixed <- df_temp$service_charge/df_temp$bill
  df_temp$percentFixed <- round(percentFixed, digits = 2)
  
  return(df_temp)
}


calculate_bills_for_all_utilities <- function(df_OWRS, supplier_report, df_sample, owrs_path, customer_classes, single_value){
  #Declare Null Data Set
  df_NA <- data.frame(
    usage_ccf = NA,
    #usage_month = NA,
    #usage_year = NA,
    cust_class = NA,
    usage_date = NA,
    service_charge = NA,
    commodity_charge = NA,
    percentFixed = NA,
    bill = NA
  )
  #End
  
  #Run through all the OWRS files and test if they are Readable and add the information to the data frame
  
  for(i in 1:nrow(df_OWRS))
  {
    row <- df_OWRS[i,]
    
    if(i==1){
      df_bill <- NULL
    }
    
    #Open OWRS file and retrieve important data
    owrs_file <- tryCatch({
      #Open OWRS file
      getFileData(owrs_path, row$filepath)
    },
    error = function(cond){
      #Display Error Message for specific files
      print(i)
      message(paste("Format error in file:", row$filepath, "\n", cond, "\n"))
      return(NULL)
    })
    
    #If there is an error format the row data accordingly
    if(!is.null(owrs_file))
    {
      
      for(j in 1:length(customer_classes))
      {
        current_class <- customer_classes[j]
        owrs_str <- jsonlite::toJSON(owrs_file$rate_structure[[current_class]])
       
        # customize the sample for each utility
        tmp_sample <- df_sample
        if(grepl('3/4', owrs_str)){
        }else if(grepl('5/8', owrs_str)){
          tmp_sample <- df_sample
          tmp_sample$meter_size <- '5/8"'
        }else{
          tmp_sample <- df_sample
          tmp_sample$meter_size <- '1"'
        }
        
        has_pressure_charge <- grepl('pressure_zone', owrs_str) | grepl('elevation_zone', owrs_str)
        if(has_pressure_charge){
          tmp_sample$has_pressure_charge <- TRUE
        }else{
          tmp_sample$has_pressure_charge <- FALSE
        }
        
        
        tmp_sample$is_single <- FALSE
        tmp_row <- tmp_sample[1,]
        tmp_row$is_single <- TRUE

        if(!is.na(row$PWSID) && nchar(row$PWSID) > 1){
          tmp_report <- supplier_report %>% 
            filter(report_pwsid == row$PWSID) %>%
                   # report_month == tmp_row$usage_month) %>%
            summarise(report_eto = mean(report_eto, na.rm=TRUE),
                      report_gpcd = mean(report_gpcd_calculated, na.rm=TRUE),
                      avg_hhsize = mean(avg_hhsize))
          
          if(!is.na(tmp_report$report_eto)){
            tmp_row$et_amount <- tmp_report$report_eto
          }
          
          if(!is.na(tmp_report$avg_hhsize)){
            tmp_row$hhsize <- tmp_report$avg_hhsize
          }
          
          if(!is.na(tmp_report$report_gpcd)){
            tmp_row$usage_ccf <- tmp_report$report_gpcd*tmp_row$hhsize*tmp_row$days_in_period/748
          }else{
            tmp_row$usage_ccf <- single_value
          }
            
        }else{
          tmp_row$usage_ccf <- single_value
        }
        tmp_sample <- bind_rows(tmp_sample, tmp_row)
        
          
        df_temp <- tryCatch({
          singleUtilitySim(tmp_sample, df_OWRS[i,], owrs_file, current_class)
        },
        error = function(cond){
          #Display Error Message for specific files
          print(i)
          message(paste("Rate calculation error in file:", df_OWRS[i,]$filepath, "\n", cond, "\n"))
          return(NULL)
        }) 
        
        if(is.null(df_bill)){
          df_bill <- df_temp
        }else{
          df_bill <- bind_rows(df_bill, df_temp)
        }
      }
    }else{
      # utility <- data.frame(utility_id = df_OWRS[i,]$utility_id, 
      #                       utility_name = df_OWRS[i,]$filename, 
      #                       bill_frequency = "NA")
      # df_temp <- data.frame(utility, df_NA)
      # df_bill <- rbind(df_bill, df_temp)
    }
  }
  
  df_bill
}


#A function to check if a service charge is present and if not adds a 0 value to the Data Frame
hasServiceCharge <- function(x) {
  if(!"service_charge" %in% colnames(x))
  {
    x$service_charge <- 0
  }
  
  return(x)
}


#A function to check if a commodity charge is present and if not adds a 0 value to the Data Frame
hasCommodityCharge <- function(x) {
  if(!"service_charge" %in% colnames(x))
  {
    x$commodity_charge <- 0
  }
  
  return(x)
}

extract_date <- function(x){
  date_pattern <- "[a-zA-Z\\s_-]*(\\d{1,4}\\-\\d{1,2}\\-\\d{1,4}).*"
  
  datestr <- gsub(x, pattern=date_pattern, replacement="\\1")
  first_dash_idx <- regexpr("-", datestr )[1]
  
  if(first_dash_idx<=3){
    date_parts <- strsplit(datestr, "-")[[1]]
    datestr <- paste(date_parts[3],date_parts[1],date_parts[2], sep="-")
  }
  
  #return(as.Date(datestr, format="%Y-%m-%d"))
  return(datestr)
}

extract_utility_name <- function(x){
  tmp <- unlist(strsplit(x, " "))
  tmp <- tmp[1:(length(tmp)-2)]
  tmp <- paste(tmp, collapse=" ")
  return(tmp)
}


#A function to retrieve Utility Rate Information from OWRS files
getFileData <- function(path, subpath){
  return(read_owrs_file(paste(c(path, "/", subpath), collapse = '')))
}


printCurrency <- function(Number){
  paste('$', Number, sep = "")
}


getFileNames <- function(path){
  #iterate through each directory and get the filenames
  file_names <- unlist(list.files(path=path, pattern = "\\.owrs$", recursive=TRUE))
  file_names <- file_names[!grepl("/[O|o]lder", file_names)] #remove subdirs "Older"
  file_names <- file_names[!grepl("/Need", file_names)] #remove subdirs "Need..."
  file_names <- file_names[!grepl("/Other", file_names)] #remove subdirs "Other"
  file_names <- file_names[!grepl("/Not", file_names)] #remove subdirs "Not.."
}


