require(httr)
require(jsonlite)
library(rvest)
library(stringr)
library(XML)


zamgerReport <- function(courseID, year, writeCSV = FALSE)
{

# get the URL from the parameters
url <- paste('https://zamger.etf.unsa.ba/?sta=izvjestaj/predmet&predmet=', courseID, '&ag=', year)

# get report from zamger and fix some html formatting errors
r <- readLines(url)
r <- str_replace_all(string = r, pattern='</td><td align="center">', repl = '</td>\n<td align="center">')
r <- str_replace_all(string = r, pattern='</td><td>', repl = '</td>\n<td>')
r <- str_replace_all(string = r, pattern='Završni', repl = 'Zavrsni')

# get the course name and fix some bosnian characters (we don't do UTF encoding because we only want english letters)
courseName <- grep('<h1>([^<]*)</h1>', r, value = TRUE)
courseName <- substring(courseName, 5, nchar(courseName)-5)
courseName <- str_replace_all(string = courseName, pattern='ž', repl='z') # afrikat
courseName <- str_replace_all(string = courseName, pattern='š', repl='s') # afrikat
courseName <- str_replace_all(string = courseName, pattern='\215', repl='c') # afrikat
courseName <- str_replace_all(string = courseName, pattern='�', repl='') # afrikat

# get each table and it's name - the name of the table is the name of the group
doc <- htmlTreeParse(r, asText = TRUE, useInternalNodes = TRUE)
f <- function(x) cbind(h2 = xmlValue(x), dd = xpathSApply(x, "//dd", xmlValue))
groups <- xpathApply(doc, "//table", f)
groupNames <- xpathApply(doc, "//h2", f)

# since we don't want lists but vectors of strings, we'll convert the groups and their names into string vectors here
# we also delete any \t to tidy up the string a bit
groupsStr <- 0
groupNamesStr <- 0
for(i in 1:length(groups))
{
  groups[[i]][1,] <- str_replace_all(string = groups[[i]][1,], pattern="\t", repl="")
  groupsStr[i] <- paste(unlist(groups[[i]][1,]), collapse='')
  groupsStr[i] <- substring(groupsStr[i], 1)
  groupNamesStr[i] <- paste(unlist(groupNames[[i]][1,]), collapse = '')
}

# now we have the groups as strings, we can now take the header of each group to determine the column names for the DF
# technically we can do this for only the first group, since all groups share the same header...
# ...but that can change in the future and determining the header for each group individually will make it easier to
# ...change our code in the future
headers <- 0
i <- 1
for(grp in groupsStr)
{
  headers[i] <- strsplit(substr(grp,1,str_locate(grp,"\n1.\n")[1]), '\n')
  i <- i + 1
}
# now we have the headers, but since the website is coded in a weird way, we need to move some things around
# in each header, we need to move "UKUPNO" and "Konacnaocjena" to the end, completely remove the entry "Ispiti" 
# ...and add the entry "Grupa" (for the group) to the end
for(i in 1:length(headers))
{
  for(j in 1:length(headers[[i]]))
  {
    if(all(headers[[i]][j] == "Ispiti") 
       || all(headers[[i]][j] == "UKUPNO")
       || all(headers[[i]][j] == "Kona�\u008dnaocjena")) headers[[i]][j] <- ""
    
    if(all(substring(headers[[i]][j],1,4) == "Zada")) headers[[i]][j] <- "Zadace"
  }
  headers[[i]] <- c(headers[[i]], "UKUPNO")
  headers[[i]] <- c(headers[[i]], "Ocjena")
  headers[[i]] <- c(headers[[i]], "Grupa")
  headers[[i]] <- headers[[1]][!headers[[1]] %in% c("")]
}

# headers are done, we now need our students
# we'll write all the students into a big list, where the last entry in the list will be the group of the student
# we take this from the variable "groupsStr"
students <- 0
index <- 1
for(grp in groupsStr)
{
  groupSplit <- unlist(strsplit(substr(grp, str_locate(grp,"\n1.\n")[1], nchar(grp)), '\n'))
  groupSplit <- groupSplit[!groupSplit %in% c("")]
  noOfAttributes <- length(headers[[1]]) - 1
  studentsgroups <- split(groupSplit, ceiling(seq_along(groupSplit)/noOfAttributes))
  
  for(i in 1:length(studentsgroups))
    studentsgroups[[i]] <- c(studentsgroups[[i]], groupNamesStr[index])
  
  students <- c(students, studentsgroups)
  index <- index + 1
}

# now we will swap "/" for "NA" since that is way more useful in a dataframe
for(i in 2:length(students))
{
  for(j in 1:length(students[[i]]))
  {
    if(all(students[[i]][j] == "/")) 
      students[[i]][j] <- NA
  }
}

# delete the first entry in the students list since it is surplus
students[1] <- NULL

# get rid of whitespaces in the header (so we can index the column names easier)
headerStr <- headers[[1]]
for(i in 1:length(headerStr))
{
  headerStr[i] <- str_replace_all(headerStr[i], "\\s", "")
}

# we have a prepared header (headerStr) and a list of all students (students) - now we can build the DF
# we can do that by combining them into one single list, and then converting that list into a dataframe
headerStr <- list(headerStr)
df <- c(headerStr, students)

df <- data.frame(matrix(unlist(df), nrow=length(df), byrow=T))

# set the column names to be the ones in the header, and remove the first row from the DF (since we don't need it anymore)
colnames(df) <- as.character(unlist(df[1,]))
df = df[-1, ]

# if the parameter for writing is true
# create a CSV file in the current directory whose name is the name of the course, and write the DF into the file
if(writeCSV == TRUE)
  write.csv(df, file = paste(courseName, ".csv", sep = ""), row.names=FALSE)

# clean up all unwanted variables
rm(groups,headers,headerStr,groupNames,students,studentsgroups,noOfAttributes,doc,grp,groupSplit,groupsStr,i,index,j,groupNamesStr,courseName,r,f)
return(df)
}

# some examples
data <- zamgerReport(4,14,TRUE) # discrete mathematics
data2 <- zamgerReport(7,14,TRUE) # operations research
data3 <- zamgerReport(2231,14,TRUE) # programming languages and compilers
data4 <- zamgerReport(2103,13,TRUE) # embedded systems
data5 <- zamgerReport(2235,14,TRUE) # computer literacy
