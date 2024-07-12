##gets files from europepmc
download_pdfs <- function(input_df, download_dir) {
  
  if (!dir.exists(download_dir)) {
    dir.create(download_dir)
  }
  
  
  # Define the Europe PMC API query
  url <- "https://www.ebi.ac.uk/europepmc/webservices/rest/searchPOST"
  
  # Loop through each row of the input dataframe using sapply
  sapply(1:nrow(input_df), function(i) {
    # Get the DOI from the current row
    doi <- input_df$doi[i]
    
    # Remove https or http://www.doi.org/ prefix from doi object
    doi <- sanitize_doi(doi)
    
    # Print the DOI for status tracking
    print(doi)
    
    # Construct the Europe PMC API query
    response <- POST(url, 
                     body = paste0("query=", doi, "&resultType-=core&pageSize=10"), 
                     encode = "form", 
                     add_headers(`Content-Type` = "application/x-www-form-urlencoded"))
    
    
    # Check if the response is successful
    stop_for_status(response)
    
    # Parse the JSON response
    json_response <- jsonlite::fromJSON(content(response, "text"), simplifyDataFrame = FALSE)  
    
    # Check if any Europe PMC search results were found for the DOI
    if (json_response$hitCount == 0) {
      message("No Europe PMC search results found for DOI:", doi, "\n")
    } else {
    
    # Check if an open-access PDF is available
      pdf_urls <- sapply(json_response$resultList$result[[1]]$fullTextUrlList, function(fulltextlist) {
        fts <- c()
        for (j in 1:length(fulltextlist)) {
          if (fulltextlist[[j]]$documentStyle == "pdf" && fulltextlist[[j]]$availability %in% c("Free", "Open access")) {
            fts <- c(fts, fulltextlist[[j]]$url)
          }
        }
        fts
      })
    
    # If no open-access PDF is available, skip to the next DOI, else do the rest of the function
    if (is.null(unlist(pdf_urls))) {
      message("No open-access PDFs found for DOI:", doi, "\n")
    } else {
      
    # Generate a rational filename for the PDF
    filename <- paste0("nftc_", doi, ".pdf")
    filename <- gsub("[^a-zA-Z0-9_.-]", "", filename)  # sanitize the filename
    
    #generate a user agent for the GET request
    user_agent <- make_user_agent()
    
    # Download the PDF, check if the downloaded pdf can be opened, if error, try next url if one is available.
    # If no pdfs can be opened, skip to next doi
    pdf_downloaded <- FALSE
    for (url in pdf_urls) {
      tryCatch({
        pdf_path <- file.path(download_dir, filename)
        GET(url, write_disk(pdf_path, overwrite = TRUE), add_headers("User-Agent" = user_agent))
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
    
    # Retrieve publication metadata from Europe PMC
    metadata <- json_response$resultList$result[[1]]
    
    # Format the publication metadata and input dataframe metadata as JSON
    metadata_attributes <- list()
    metadata_attributes <- c(metadata_attributes, list("doi" = input_df$doi[i]))
    metadata_attributes <- c(metadata_attributes, list("title" = input_df$publicationTitle[i]))
    metadata_attributes <- c(metadata_attributes, list("author" = input_df$author[i]))
    
    # Add Europe PMC metadata
    metadata_attributes <- c(metadata_attributes, list("pmcid" = metadata$pmcid))
    metadata_attributes <- c(metadata_attributes, list("pmid" = metadata$pmid))
    metadata_attributes <- c(metadata_attributes, list("author" = metadata$author))
    metadata_attributes <- c(metadata_attributes, list("journal" = metadata$journal))
    metadata_attributes <- c(metadata_attributes, list("publication_date" = metadata$publicationDate))
    metadata_attributes <- c(metadata_attributes, list("abstract" = metadata$abstract))
    
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
    }
    })
}


download_pdfs(input_df, download_dir = '~/Downloads/nftc_pdfs_europepmc/')


## function to delete pdfs that have no associated metadata.json file (e.g. cleanup...)
delete_pdfs <- function(download_dir) {
  pdf_files <- list.files(download_dir, pattern = "\\.pdf$", full.names = TRUE)
  metadata_files <- list.files(download_dir, pattern = "\\.metadata\\.json$", full.names = TRUE)
  
  pdf_files_to_delete <- setdiff(pdf_files, gsub("\\.metadata\\.json$", "", metadata_files))
  
  for (pdf_file in pdf_files_to_delete) {
    file.remove(pdf_file)
  }
}

delete_pdfs(download_dir)




##write a function to clean up the json files
## json files cannot have nested lists, so we need to flatten the json files
## json files cannot have blank values, so we need to remove blank values
## json files cannot have duplicate keys, so we need to remove duplicate keys
## assume 100 characters max for a value, so remove key-value pairs with values longer than 100 characters
## write cleaned json files to a different directory for testing

clean_json_files <- function(download_dir) {
  json_files <- list.files(download_dir, pattern = "\\.metadata\\.json$", full.names = TRUE)
  
  for (json_file in json_files) {
    # Flatten the JSON object
    json_data <- flatten_json(json_file)
    
    # Remove blank values
    json_data <- json_data[sapply(json_data, function(x) !is.null(x) && x != "" && nchar(as.character(x)) <= 100)]
    
    # Remove duplicate keys
    json_data <- json_data[!duplicated(names(json_data))]

    jsonlite::write_json(json_data, json_file, pretty = TRUE)
  }
}


flatten_json <- function(json_obj) {
  json_obj <- jsonlite::fromJSON(json_obj)
  
  flatten_recursive <- function(x, prefix = "") {
    if (is.list(x)) {
      out <- list()
      for (i in seq_along(x)) {
        key <- names(x)[i]
        if (is.list(x[[i]])) {
          out <- c(out, flatten_recursive(x[[i]], paste0(prefix, key, ".")))
        } else {
          out <- c(out, setNames(list(x[[i]]), paste0(prefix, key)))
        }
      }
      return(out)
    } else {
      return(x)
    }
  }
  
  flat_obj <- flatten_recursive(json_obj$metadataAttributes)
  return(flat_obj)
}

clean_json_files(download_dir)
json_file <- json_files[[1]]



# function to read in each json to repair
# nest every key-value pair under a key called "metadataAttributes"

repair_json_files <- function(download_dir) {
  json_files <- list.files(download_dir, pattern = "\\.metadata\\.json$", full.names = TRUE)
  
  for (json_file in json_files) {
    json_data <- jsonlite::fromJSON(json_file)
    
    # Create a new list with the metadataAttributes key
    new_json_data <- list(metadataAttributes = json_data)
    
    # Write the repaired JSON file
    jsonlite::write_json(new_json_data, json_file, pretty = TRUE)
  }
}


repair_json_files(download_dir)



## read in json files, retain only the doi key under metadataAttributes, and write the json files back to the directory
retain_doi_key <- function(download_dir) {
  json_files <- list.files(download_dir, pattern = "\\.metadata\\.json$", full.names = TRUE)
  
  for (json_file in json_files) {
    json_data <- jsonlite::fromJSON(json_file)
    
    # Retain only the DOI key under metadataAttributes
    new_json_data <- list(metadataAttributes = list(doi = json_data$metadataAttributes$doi))
    
    # Write the repaired JSON file
    jsonlite::write_json(new_json_data, json_file, pretty = TRUE)
  }
}

retain_doi_key(download_dir = 'Downloads/nftc_files_europe')

