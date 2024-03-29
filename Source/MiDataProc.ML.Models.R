library(stringr)
library(chatgpt)
library(ROCR)
library(caret)

# Essentials ----------------

colnames.to.ind <- function(data){ # data list containing phylum ~ species datasets
  origin <- list()
  new <- list()
  for(name in names(data)){
    ind.dat <- data[[name]]
    col.names <- colnames(ind.dat)
    new.names <- character()
    first.letter <- str_to_upper(substr(name, 1, 1))
    for(i in 1:length(col.names)){
      new.names <- c(new.names, sprintf("%s%i", first.letter, i))
    }
    origin[[name]] <- col.names
    new[[name]] <- new.names
  }
  return(list(origin = origin, new = new))
}

colnames.df <- function(colnames.list, name){
  d <- data.frame(colnames.list$origin[[name]])
  rownames(d) <- colnames.list$new[[name]]
  colnames(d) <- str_to_title(name)
  return(d)
}

change.colnames <- function(data, new.names){
  for(name in names(data)){
    colnames(data[[name]]) <- new.names[[name]]
  }
  return(data)
}

get.confusion.matrix <- function(fit){
  ncol <- dim(fit$finalModel$confusion)[1]
  return(fit$finalModel$confusion[,-ncol])
}

get.oob <- function(c.matrix){
  return((sum(c.matrix) - sum(diag(c.matrix)))/sum(c.matrix))
}

get.acc <- function(pred.class, test.y){
  return(mean(pred.class == test.y))
}

get.auc <- function(pred.prob, test.y){
  auc.pred <- prediction(pred.prob, test.y)
  return(as.numeric(performance(auc.pred, "auc")@y.values))
}

get.ce <- function(pred.prob, test.y){
  ce <- 0
  test.y.df <-  data.frame(test.y)
  dummy <- dummyVars("~.", data = test.y.df)
  test.y <- data.frame(predict(dummy, newdata = test.y.df))
  
  for(j in 1:length(pred.prob[,2])){
    ce <- ce + as.numeric(test.y[j,]) %*% log(as.numeric(pred.prob[j,]))
  }
  return(-as.numeric(ce))
}

get.mse <- function(pred, test.y){
  return(mean((pred - test.y)^2))
}

get.mae <- function(pred, test.y){
  return(mean(abs(pred - test.y)))
}

get.r2 <- function(pred, test.y){
  return(cor(pred, test.y)^2)
}

"%notin%" <- Negate("%in%")

get.level.names <- function(include = TRUE){
  if(!include){
    return(c("phylum", "class", "order", "family", "genus"))
  }
  return(c("phylum", "class", "order", "family", "genus", "species"))
}

get.mean.abundance <- function(data, rank.name){
  return(colMeans(data[[rank.name]]))
}

remove.na <- function(data, sam.dat, y.name, level.names){
  ind1 <- which(is.na(sam.dat[[y.name]]))
  ind2 <- which(sam.dat[[y.name]] == -9.00 | sam.dat[[y.name]] == -99.00 | sam.dat[[y.name]] == -999.00)
  ind <- sort(c(ind1, ind2))
  if(length(ind) > 0){
    sam.dat.na <- sam.dat[-ind,]
    for(name in level.names){
      data[[name]] <- data[[name]][-ind,]
    }
  }
  else {
    sam.dat.na <- sam.dat
  }
  return(list(data = data, sam.dat.na = sam.dat.na))
}

category.names <- function(sam.dat, y.name){
  return(names(table(sam.dat[[y.name]])))
}

str.check <- function(sam.dat, y.name){
  out <- character()
  var <- sam.dat[[y.name]]
  len <- length(table(var))
  if(len == 2){
    return("Binary")
  }
  else if(len >= 3 & len <= 8){
    return("Multinomial")
  }
  else if(len > 8 & is.numeric(var)){
    return("Continuous")
  }
  else {
    return("Neither")
  }
}

bmc.col.check <- function(sam.dat, type = c("Binary", "Multinomial", "Continuous")){
  dtype.vector <- character()
  for(name in colnames(sam.dat)){
    dtype.vector <- c(dtype.vector, str.check(sam.dat, name))
  }
  ind <- which(dtype.vector == type)
  return(colnames(sam.dat[,ind]))
}

col.str.check <- function(sam.dat, name){
  dtype <- character()
  if(length(table(sam.dat[[name]])) == 1){
    dtype <- "none"
  }
  else if((is.character(sam.dat[[name]])) | (is.factor(sam.dat[[name]]))) {
    if(length(unique(sam.dat[[name]])) == nrow(sam.dat)){
      dtype <- "none"
    }
    else{
      dtype <- "factor"
    }
  }
  else if(is.numeric(sam.dat[[name]])){
    if(length(table(sam.dat[[name]])) == 2){
      dtype <- "factor"
    }
    else if(length(unique(sam.dat[[name]])) == nrow(sam.dat)){
      dtype <- "none"
    }
    else{
      dtype = "numeric"
    }
  }
  else{
    dtype = "none"
  }
  return(dtype)
}

get.cov.col <- function(sam.dat){
  dtype <- character()
  names <- colnames(sam.dat)
  for(name in names){
    dtype <- c(dtype, col.str.check(sam.dat, name))
  }
  cov.col <- names[dtype != "none"]
  return(cov.col)
}

get.cat.levels <- function(sam.dat, y.name){
  levels <- levels(as.factor(unlist(sam.dat$gingival_index)))
  if(length(levels) >= 2 & length(levels) <= 8){
    return(levels)
  }
  else{
    stop(sprintf("%s is not categorical variable.", y.name))
  }
}

remove.symb <- function(X){
  rep_str <- c("-" = "_", ";" = "_", ":" = "_", " " = "_", "\\(" = "", "\\)" = "", "\\]" = "", "\\[" = "", "\\*" = "_", "^" = "_", "&" = "_", "\\=" = "_", "\\." = "")
  colnames(X) <- str_replace_all(colnames(X), rep_str)
  colnames(X) <- substr(colnames(X), 2, nchar(colnames(X)))
  return(X)
}

cov.remove.na <- function(data, sam.dat, y.name, cov.name, level.names){
  new.sam.dat <- sam.dat[,c(cov.name, y.name)]
  ind <- sort(as.vector(which(is.na(new.sam.dat), arr.ind = TRUE)[,1]))
  if(length(ind) > 0){
    sam.dat.na <- new.sam.dat[-ind,]
    for(name in level.names){
      data[[name]] <- data[[name]][-ind,]
    }
  }
  else {
    sam.dat.na <- new.sam.dat
  }
  return(list(data = data, sam.dat.na = sam.dat.na))
}

cov.linear.reg <- function(sam.dat, y.name){
  f1 <<- as.formula(paste(y.name, "~", ".", sep=" "))
  fit <- lm(f1, data = data.frame(sam.dat))
  resid <- resid(fit)
  sam.dat.resid <- cbind(sam.dat, resid)
  return(sam.dat.resid)
}

cov.logistic.reg <- function(sam.dat, y.name){
  f1 <<- as.formula(paste(y.name, "~", ".", sep=" "))
  fit <- glm(f1, data = data.frame(sam.dat), family = "binomial")
  resid <- residuals(fit, type = "pearson")
  sam.dat.resid <- cbind(sam.dat, resid)
  return(sam.dat.resid)
}

chat_gpt_MiTree <- function(taxa.name, var.name, api.key){
  Sys.setenv(OPENAI_API_KEY = api.key)
  past_question <- paste("Tell me about the roles of", taxa.name, "on", var.name)
  chat <- ask_chatgpt(past_question)
  return(chat)
}

check.column.class <- function(sam.dat.na){
  for(name in colnames(sam.dat.na)){
    type <- col.str.check(sam.dat.na, name)
    if(type == "factor"){
      sam.dat.na[[name]] <- as.factor(sam.dat.na[[name]])
    }
    else if(type == "numeric"){
      sam.dat.na[[name]] <- as.numeric(sam.dat.na[[name]])
    }
    else{
      sam.dat.na[[name]] <- sam.dat.na[[name]]
    }
  }
  return(sam.dat.na)
}

