library(tidyverse)
library(googlesheets4)
library(synapser)

synLogin()
gs4_auth()

# Set the directory path
directory <- "./nftc_observations"

# Get the list of files in the directory
files <- list.files(directory, pattern = "observation_")

# Combine the data from all files into a single data frame
combined_data <- files %>%
    map_df(~ read_csv(file.path(directory, .x)) %>%
                        mutate(resourceId_reference = str_remove(str_remove(.x, "observation_"), "\\.csv")),
                 .id = NULL) %>% 
  distinct()

# Write the combined data to a new file
write_csv(combined_data, file = "combined_observations.csv")



# Read in the data from the Google Sheet
curated_data <- read_sheet("1bVao_qOI7fyVCmge4r7JEOAL7I4SbjlTMzV6haTA5DU")

#replace https://doi with https://www.doi
curated_data$doi <- gsub("https://doi.org", "https://www.doi.org", curated_data$doi)

#get the species syn51735419
species_table <- synTableQuery("select resourceId, species from syn51735419")$asDataFrame()

#join the species table to the curated data
curated_data <- left_join(curated_data, species_table, by = "resourceId") %>% 
  #replace all NA string values with true NA
  mutate_all(~na_if(unlist(.), "NA")) %>% 
  #convert species column from json to string
  mutate(species = str_replace_all(species, "\\[|\\]|\"", ""))

#using the phase table syn52408661 on synapse.org, get the phaseId and phaseName, and join to the curated data
# Get the phase table
phase_table <- synTableQuery("select species, observationPhase, observationTimeMax, observationTimeUnits from syn52408661")$asDataFrame()


## first, mutate observation time in curated_data  to double
## then, mutate and combine the observationTime and observationTimeUnits to days
## eg. 14 days and 2 weeks should be converted to days

curated_data_2 <- curated_data %>% 
  mutate(observationTime = as.numeric(observationTime)) %>% 
  mutate(observationTime = case_when(
    observationTimeUnits == "days" ~ observationTime,
    observationTimeUnits == "weeks" ~ observationTime * 7,
    observationTimeUnits == "months" ~ observationTime * 30,
    observationTimeUnits == "years" ~ observationTime * 365
  )) %>% 
  mutate(observationTimeUnits = case_when(
    !is.na(observationTimeUnits) ~ 'days',
    is.na(observationTimeUnits) ~ NA_character_
  )) %>% 
  #currently no timeline support for cell lines, so lets remove timepoints so they show up on the portal
  mutate(observationTime = case_when(
    resourceType == "['Cell Line']" ~ NA_real_,
    resourceType != "['Cell Line']" ~ observationTime
    ),
    observationTimeUnits = case_when(
      resourceType == "['Cell Line']" ~ NA_character_,
      resourceType != "['Cell Line']" ~ observationTimeUnits)
  ) %>% 
  #if observationTime is NA, set observationTimeUnits to NA
  mutate(observationTimeUnits = case_when(
    is.na(observationTime) ~ NA_character_,
    !is.na(observationTime) ~ observationTimeUnits
  ))
    

#using the information in the observation phase table, species, observationPhase, observationTimeMax and observationTimeUnits, 
##correct the phases in the curated data based on the species and time information
##do not use a join this is a mapping exercise

curated_data_3 <- curated_data_2 %>%
  mutate(observationPhase = case_when(
    # Mus musculus
    species == 'Mus musculus' & observationPhase %in% c('prenatal', 'embryonic') ~ 'prenatal',
    species == 'Mus musculus' & !observationPhase %in% c('prenatal', 'embryonic') ~ 'postnatal',
    
    # Sus scrofa
    species == 'Sus scrofa' & observationPhase == 'prenatal' ~ 'prenatal',
    species == 'Sus scrofa' & observationPhase != 'prenatal' & observationTime <= 3 * 30 ~ 'neonatal',
    species == 'Sus scrofa' & observationPhase != 'prenatal' & observationTime > 3 * 30 & observationTime <= 6 * 30 ~ 'weanling',
    species == 'Sus scrofa' & observationPhase != 'prenatal' & observationTime > 6 * 30 & observationTime <= 12 * 30 ~ 'juvenile',
    species == 'Sus scrofa' & observationPhase != 'prenatal' & observationTime > 12 * 30 & observationTime <= 2 * 365 ~ 'adolescent',
    species == 'Sus scrofa' & observationPhase != 'prenatal' & observationTime > 2 * 365 ~ 'adult',
    
    # Danio rerio
    species == 'Danio rerio' & observationPhase == 'embryonic' ~ 'embryo',
    species == 'Danio rerio' & !observationPhase %in% c('embryonic', 'embryo') & observationTime <= 3 * 30 ~ 'larval',
    species == 'Danio rerio' & !observationPhase %in% c('embryonic', 'embryo') & observationTime > 3 * 30 & observationTime <= 6 * 30 ~ 'juvenile',
    species == 'Danio rerio' & !observationPhase %in% c('embryonic', 'embryo') & observationTime > 6 * 30 ~ 'adult',
    
    # Drosophila
    species == 'Drosophila' & observationPhase == 'embryo' ~ 'embryo',
    species == 'Drosophila' & observationPhase != 'embryo' & observationTime <= 5 * 24 ~ 'larval',
    species == 'Drosophila' & observationPhase != 'embryo' & observationTime > 5 * 24 & observationTime <= 12 * 24 ~ 'pupal',
    species == 'Drosophila' & observationPhase != 'embryo' & observationTime > 12 * 24 ~ 'adult',
    
    # Rattus norvegicus
    species == 'Rattus norvegicus' & observationPhase == 'prenatal' ~ 'prenatal',
    species == 'Rattus norvegicus' & observationPhase == 'neonatal' & observationTime <= 4 * 7 ~ 'neonatal',
    species == 'Rattus norvegicus' & observationPhase == 'weanling' & observationTime > 4 * 7 & observationTime <= 2 * 30 ~ 'weanling',
    species == 'Rattus norvegicus' & observationPhase == 'juvenile' & observationTime > 2 * 30 & observationTime <= 3 * 30 ~ 'juvenile',
    species == 'Rattus norvegicus' & observationPhase == 'adolescent' & observationTime > 3 * 30 & observationTime <= 6 * 30 ~ 'adolescent',
    species == 'Rattus norvegicus' & observationPhase == 'adult' & observationTime > 6 * 30 ~ 'adult',
    
    TRUE ~ observationPhase
  )) %>% 
  select(-ROW_ID, -ROW_VERSION) %>% 
  #remove columns where pub is missing 
  filter(!is.na(doi))


# Get the publication table
publication_table <- synTableQuery("select publicationId, doi from syn26486839")$asDataFrame()


# Join the publication table to the curated data
curated_data_4 <- left_join(curated_data_3, publication_table, by = "doi")

#filter where ROW_ID is not NA
curated_data_5 <- curated_data_4 %>% 
  filter(!is.na(ROW_ID)) %>% 
  select(-ROW_ID, -doi, -resourceId_reference, -ROW_VERSION, -resourceName, -resourceType) %>% 
  #add Component column with value Observation
  mutate(Component = "Observation") %>% 
  mutate(observationSubmitterName = "🤖 AI-extracted - IN BETA - please confirm accuracy in linked publication") %>% 
  #add blank columns for  `observationId`, `synapseId`, `reliabilityRating`, `easeOfUseRating`, and `observationLink`
  mutate(observationId = NA, synapseId = NA, reliabilityRating = NA, easeOfUseRating = NA, observationLink = NA) %>% 
  #reformat observationType from json string to comma separated string
  mutate(observationType = str_replace_all(observationType, "\\[|\\]|\"", ""))  %>% 
  #also remove ' from observationType
  mutate(observationType = str_replace_all(observationType, "'", "")) 

#get observation template from google sheets (/1j47_gcaQnaPekAE3czgI8oTnGw_U5fMrOj6nxp5n-kU)
observation_template <- read_sheet("1j47_gcaQnaPekAE3czgI8oTnGw_U5fMrOj6nxp5n-kU")

#make sure all columns in the observation_template are in the curated_data_2, and in the correct order
curated_data_6 <- curated_data_5 %>% 
  select(names(observation_template))

#append curated_data_2 to observation_template google sheet
write_sheet(curated_data_6, "1j47_gcaQnaPekAE3czgI8oTnGw_U5fMrOj6nxp5n-kU", sheet = "June-14-2024")
  