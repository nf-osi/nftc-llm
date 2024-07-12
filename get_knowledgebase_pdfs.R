## This script downloads PDFs from the Europe PMC API for a list of DOIs and generates a metadata JSON file for each PDF.
## The metadata JSON file includes information such as the DOI, title, author, journal, publication date, and abstract.
## Both the PDFs and metadata files will be uploaded to an S3 bucket for use in an Amazon Bedrock knowledge base.

# Load required libraries
library(httr)
library(jsonlite)
library(stringr)
library(uuid)
library(openssl) 

# Function to generate a random string of a given length
random_string <- function(length = 10) {
  paste0(sample(c(0:9, letters, LETTERS), length, replace = TRUE), collapse = "")
}

# Function to generate a random base64-encoded string
random_base64 <- function(length = 16) {
  base64_encode(rand_bytes(length))
}

# Function to generate current date time in HTTP date format
http_date <- function() {
  as.character(format(Sys.time(), "%a, %d %b %Y %H:%M:%S GMT"))
}

# Function to generate a random header
synthesize_random_header <- function(user_agent) {
  c(
    Authorization = paste("Bearer", UUIDgenerate()),
    `Content-Type` = "application/json",
    `X-Custom-Header` = random_string(16),
    `X-Request-ID` = UUIDgenerate(),
    `X-Client-ID` = random_string(8),
    `X-Session-Token` = random_base64(32),
    `User-Agent` = user_agent,
    `X-Timestamp` = http_date()
  )
}

## Function to synthesize a user agent for the GET request
make_user_agent <- function() {
  os_platform <- sample(c("Windows NT 10.0", "Windows NT 6.1", "Macintosh; Intel Mac OS X 10_15_7", "X11; Linux x86_64"), 1)
  browser <- sample(c("Chrome", "Firefox", "Safari", "Edge"), 1)
  browser_version <- paste0(" ", sample(c("80.0.3987.149", "81.0.4044.138", "85.0.4183.102", "89.0.4389.90"), 1))
  language <- sample(c("en-US", "en-GB", "fr-FR", "de-DE"), 1)
  
  user_agent <- paste0("Mozilla/5.0 (", os_platform, "; ", browser, browser_version, "; ) AppleWebKit/537.36 (KHTML, like Gecko) ", browser, " ", browser_version, " ", language)
  
  return(user_agent)
}


#Sanitize doi
sanitize_doi <- function(doi) {
  doi <- gsub("https://www.doi.org/", "", doi)
  doi <- gsub("https://doi.org/", "", doi)
  return(doi)
}


# Set the input dataframe and directory paths
input_df <- read.csv("Downloads/nftc_publications.csv")
download_dir <- "Downloads/nftc_pdfs_europe"

# Create the download directory if it doesn't exist
if (!dir.exists(download_dir)) {
  dir.create(download_dir)
}

#####################
#this just allows you to run the file multiple times in case there are server issues and not have to re-download everything
## read all json files and create a list of dois for which pdfs were successfully downloaded
json_files <- list.files(download_dir, pattern = "\\.metadata\\.json$", full.names = TRUE)
downloaded_dois <- lapply(json_files, function(file) {
  json_data <- jsonlite::fromJSON(file)
  json_data$metadataAttributes$doi
})

## generate list of dois for which pdfs were not successfully downloaded
failed_dois <- setdiff(input_df$doi, unlist(downloaded_dois))
input_df <- input_df[input_df$doi %in% failed_dois, ]
#####################

##randomize order to avoid rate limiting by hitting the same journal multiple times in a row
input_df <- input_df[sample(nrow(input_df)), ]

## download_pdfs function, but to get pdfs from unpaywall dois
download_unpaywall_pdfs <- function(input_df, download_dir, email_address, no_header = FALSE) {
  
  
  # Loop through each row of the input dataframe using sapply
  sapply(1:nrow(input_df), function(i) {
    # Get the DOI from the current row
    doi <- input_df$doi[i]
    
    # Remove https://www.doi.org/ prefix from doi object
    doi <- sanitize_doi(doi)
    
    # Print the DOI for status tracking
    print(doi)
    
   
        # Generate a rational filename for the PDF
        filename <- paste0("nftc_", doi, ".pdf")
        filename <- gsub("[^a-zA-Z0-9_.-]", "", filename)  # sanitize the filename
        
        ## unpaywall API endpoint
        unpaywall_url <- "https://api.unpaywall.org/v2/"
        
        ## get the pdf link from the unpaywall API
        unpaywall_response <- GET(paste0(unpaywall_url, doi, "?email=",email_address))
        
        # Check if the response is successful
        warn_for_status(unpaywall_response)
        
        # Parse the JSON response, utf-8 encoding
        unpaywall_json_response <- jsonlite::fromJSON(content(unpaywall_response, "text", encoding = "UTF-8"
        ), simplifyDataFrame = FALSE)
        
        # get all url_for_pdf from the oa_locations where it is not null
        pdf_urls <- sapply(unpaywall_json_response$oa_locations, function(location) {
          location$url_for_pdf
        })
        
        #remove null values
        pdf_urls <- pdf_urls[!sapply(pdf_urls, is.null)]
        
        #generate a user agent for the GET request
        user_agent <- make_user_agent()
        headers <- synthesize_random_header(user_agent) 
        
        # Download the PDF, check if the downloaded pdf can be opened, if error, try next url if one is available.
        # If no pdfs can be opened, skip to next doi
        pdf_downloaded <- FALSE
        for (url in pdf_urls) {
          tryCatch({
            pdf_path <- file.path(download_dir, filename)
            if(no_header){
              GET(url, write_disk(pdf_path, overwrite = TRUE))
            }else{
              GET(url, write_disk(pdf_path, overwrite = TRUE), add_headers(headers))
            }
            pdf_text <- pdftools::pdf_text(pdf_path)
            pdf_downloaded <- TRUE
            break
          }, error = function(e) {
            #delete broken pdf
            file.remove(pdf_path)
            message("Error reading PDF:", e$message, "\n")
          })
          
          if (pdf_downloaded) {
            break
          }
        }
        if (!pdf_downloaded) {
          message("No PDFs could be downloaded and opened for DOI:", doi, "\n")
        }else{
          

          # Format the publication metadata and input dataframe metadata as JSON
          metadata_attributes <- list()
          metadata_attributes <- c(metadata_attributes, list("doi" = input_df$doi[i]))
          
          # Create the JSON object
          json_obj <- list(metadataAttributes = metadata_attributes)
          
          # Save the JSON file
          json_file <- paste0(filename, ".metadata.json")
          json_file_path <- file.path(download_dir, json_file)
          jsonlite::write_json(json_obj, json_file_path, pretty = TRUE)
          
          # Print a success message
          message("Successfully downloaded and processed ", doi, "\n")
        }
  })
}

    
#get as many remaining pdfs as possible from unpaywall. this may get preprints instead of final pub depending on the order of pdfs in the unpaywall response
download_unpaywall_pdfs(input_df, download_dir, email_address = "nf-osi@sagebionetworks.org", no_header = T)

## function to use unpaywall api to determine if there are any oa locations for a given doi
get_unpaywall_oa_locations <- function(input_df, email_address) {
  
  # Loop through each row of the input dataframe using sapply
  lapply(1:nrow(input_df), function(i) {
    # Get the DOI from the current row
    doi <- input_df$doi[i]
    
    # Remove https://www.doi.org/ prefix from doi object
    doi <- sanitize_doi(doi)
    
    # Print the DOI for status tracking
    print(doi)
    
    ## unpaywall API endpoint
    unpaywall_url <- "https://api.unpaywall.org/v2/"
    
    ## get the pdf link from the unpaywall API
    unpaywall_response <- GET(paste0(unpaywall_url, doi, "?email=",email_address))
    
    if (status_code(unpaywall_response) == 404) {
      message("No unpaywall locations found for ", doi, "\n")
      return(data.frame(doi = input_df$doi[i], oa_locations = NA))
    }
    
    # Check if the response is successful
    stop_for_status(unpaywall_response)
    
    # Parse the JSON response, utf-8 encoding
    unpaywall_json_response <- jsonlite::fromJSON(content(unpaywall_response, "text", encoding = "UTF-8"
    ), simplifyDataFrame = FALSE)
    
    # get all url_for_pdf from the oa_locations where it is not null
    pdf_urls <- sapply(unpaywall_json_response$oa_locations, function(location) {
      c(location$url_for_pdf, location$url)
    })
    
    #remove null values
    pdf_urls <- pdf_urls[!sapply(pdf_urls, is.null)]
    
    if(is.null(unlist(pdf_urls))){
      message("No pdf urls found for ", doi, "\n")
      return(data.frame(doi = input_df$doi[i], oa_locations = NA))
    }
    
    # Print a success message
    message("Successfully retrieved unpaywall locations for ", doi, "\n")
    
    # if no unpaywall urls are found, return a data frame with the dois and NA for the oa locations
    
    if (is.null(unlist(pdf_urls))) {
      data.frame(doi = doi, oa_locations = NA)
    } else {
      # return a tibble with the dois and the oa locations
      tibble::tibble(doi = doi, oa_locations = unlist(pdf_urls))
    }
  }) %>% dplyr::bind_rows()
  
}

unpaywall_locations <- get_unpaywall_oa_locations(input_df, "nf-osi@sagebionetworks.org")

## function to download pdfs from individual url
add_publication_manually <- function(pdf_url, doi, input_df, download_dir, no_header) {
  
  doi <- sanitize_doi(doi)
  
  # Generate a rational filename for the PDF
  filename <- paste0("nftc_", doi, ".pdf")
  filename <- gsub("[^a-zA-Z0-9_.-]", "", filename)  # sanitize the filename
  
  #generate a user agent for the GET request
  user_agent <- make_user_agent()
  headers <- synthesize_random_header(user_agent) 
  
  # Download the PDF, check if the downloaded pdf can be opened, if error, try next url if one is available.
  # If no pdfs can be opened, skip to next doi
  pdf_downloaded <- FALSE
  tryCatch({
    pdf_path <- file.path(download_dir, filename)
    if(no_header){
      GET(pdf_url, write_disk(pdf_path, overwrite = TRUE))
    }else{
      GET(pdf_url, write_disk(pdf_path, overwrite = TRUE), add_headers(headers))
    }
    pdf_text <- pdftools::pdf_text(pdf_path)
    pdf_downloaded <- TRUE
  }, error = function(e) {
    #delete broken pdf
    file.remove(pdf_path)
    message("Error reading PDF:", e$message, "\n")
  })
  
  if (!pdf_downloaded) {
    message("No PDFs could be downloaded and opened for DOI:", doi, "\n")
  }else{
    
    
    metadata_df <- input_df[sanitize_doi(input_df$doi) == doi, ]
    
    # Format the publication metadata and input dataframe metadata as JSON
    metadata_attributes <- list()
    metadata_attributes <- c(metadata_attributes, list("doi" = metadata_df$doi))
    
    # Create the JSON object
    json_obj <- list(metadataAttributes = metadata_attributes)
    
    # Save the JSON file
    json_file <- paste0(filename, ".metadata.json")
    json_file_path <- file.path(download_dir, json_file)
    jsonlite::write_json(json_obj, json_file_path, pretty = TRUE)
    
    # Print a success message
    message("Successfully downloaded and processed ", doi, "\n")
  }
  
}

unpaywall_locations <- dplyr::filter(unpaywall_locations, !is.na(oa_locations)) %>% unique()

add_publication_manually('https://journals.sagepub.com/doi/pdf/10.1369/jhc.5A6784.2005',
                         unpaywall_locations$doi[26], 
                         input_df, 
                         download_dir,
                         no_header = F)

pmc <- dplyr::filter(unpaywall_locations, str_detect(oa_locations, "pmc"))

for(i in 1:nrow(pmc)){
  print(glue::glue('{pmc$oa_locations[i]}/pdf/main.pdf'))
  add_publication_manually(glue::glue('{pmc$oa_locations[i]}/pdf/main.pdf'), 
                           pmc$doi[i], 
                           input_df, 
                           download_dir,
                           no_header = F)
}



unpaywall_locations <- dplyr::filter(unpaywall_locations, !is.na(oa_locations)) %>% unique()



##For remainder we have to manually download, rename to standard name, and create metadata.json file
## this function renames the pdfs to the standard name and creates the metadata.json file, 
## assuming downloaded file is in the download_dir and named foo.pdf
## and doi is provided as a string

rename_pdf_and_create_metadata <- function(doi, download_dir, input_pdf = "foo.pdf"){
  #sanitize doi
  sanitized_doi <- sanitize_doi(doi)
  
  filename <- paste0("nftc_", sanitized_doi, ".pdf")
  filename <- gsub("[^a-zA-Z0-9_.-]", "", filename)  # sanitize the filename
  file.rename(file.path(download_dir, input_pdf), file.path(download_dir, filename))
  
  # Format the publication metadata and input dataframe metadata as JSON
  metadata_attributes <- list()
  metadata_attributes <- c(metadata_attributes, list("doi" = doi))
  
  # Create the JSON object
  json_obj <- list(metadataAttributes = metadata_attributes)
  
  # Save the JSON file
  json_file <- paste0(filename, ".metadata.json")
  json_file_path <- file.path(download_dir, json_file)
  jsonlite::write_json(json_obj, json_file_path, pretty = TRUE)
  
  # Print a success message
  message("Successfully renamed ", doi, "\n")
}

rename_pdf_and_create_metadata('https://doi.org/10.1006/viro.1997.8597', download_dir, 'foo.pdf')
