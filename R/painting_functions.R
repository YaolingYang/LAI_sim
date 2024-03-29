# compute the genetic distance in Morgan
get_gd <- function(map,rate=NULL){
  # if the map file doesn't have a recombination distance
  if(all(!map[,1])){
    if(is.null(rate)){
      rate=1e-8
    }
    return(map[,2]*rate)
  }else{
    return(map[,1])
  }
}

## assume we get a single file called matchdata
## It includes 4 columns, which are ref_ind, mod_ind, match_start and match_end
## the ref_ind ranges from 1 to sum(n_ref_ancestry)
data_process <- function(matchdata,gd){
  # matchdata is the original match data
  # gd is the genetic position of each SNP in Morgan
  colnames(matchdata)=c('ref_ind','mod_ind','start','end')
  matchdata[,2]=as.numeric(gsub('q','',matchdata[,2]))+1
  #if(!is.null(i)){
  #  matchdata=matchdata[which(matchdata[,2]==i),]
  #}
  matchdata[,1]=matchdata[,1]+1
  matchdata[,3]=as.numeric(gsub('[','',gsub(',','',matchdata[,3]),fixed=TRUE))+1
  matchdata[,4]=as.numeric(gsub(')','',matchdata[,4]))
  matchdata=data.frame(matchdata,length=gd[matchdata$end]-gd[matchdata$start])
  return(matchdata)
}

# estimate \rho using Viterbi algorithm
est_rho_Viterbi <- function(match,gd){
  # match is the match data after data_process
  # i is the index of target individual
  #data=match[which(match$mod_ind==i),c(3,4)]
  data=match[,c(3,4)]
  nsnp=length(gd)
  # recombination position
  rec_pos=vector()
  j=1
  while(j<nsnp){
    data_use=data[which(data$start<=j & data$end>=j),]
    if(nrow(data_use)==0){
      rec_pos=c(rec_pos,j+1)
      j=j+1
    }else{
      if(max(data_use$end)<nsnp){
        rec_pos=c(rec_pos,max(data_use$end)+1)
      }
      j=max(data_use$end)+1
    }
  }
  n_rec=length(rec_pos)
  return(n_rec/(gd[nsnp]-gd[1]))
}

est_rho_EM <- function(match,gd,n_ref_each,ite_time=20,theta){
  nsnp=length(gd)
  rho_ite <- 400000/sum(n_ref_each)
  
  n_ref=sum(n_ref_each)
  nsnp=length(gd)
  matchmat=matchmatrix(match,n_ref,nsnp,theta)
  
  times=0
  
  while(times<=ite_time){
    
    #match=data_process(matchdata,gd,i)
    
    sameprob=cal_sameprob(nsnp,rho_ite,gd)
    
    forward = cal_forward(matchmat,nsnp,n_ref,sameprob)
    
    forward_prob = forward[[1]]
    log_multiF = forward[[2]]
    
    backward = cal_backward(matchmat,nsnp,n_ref,sameprob)
    
    backward_prob = backward[[1]]
    log_multiB = backward[[2]]
    
    gl <- vector()
    u <- vector()
    for(j in 1:(nsnp-1)){
      
      gl[j]=(gd[j+1]-gd[j])
      
      al <- exp(log_multiF[j+1]+log_multiB[j+1]-log_multiF[nsnp])
      ar <- exp(log_multiF[j]+log_multiB[j+1]-log_multiF[nsnp])
      u[j] <- sum(al*forward_prob[,j+1]*backward_prob[,j+1]-
                    ar*forward_prob[,j]*backward_prob[,j+1]*matchmat[,j+1]*sameprob[j])
    }
    
    rho_ite <- sum(u*rho_ite*gl/(1-sameprob))/sum(gl)
    times=times+1
  }
  
  return(rho_ite)
}



est_rho_all <- function(n_ref_each,gd,method='Viterbi',
                        matchtype='target',fix_rho=TRUE,ite_time=20,
                        N=NULL,theta,diploid=FALSE){
  rho_all=vector()
  if(matchtype=='donor'){
    sum_ind=sum(n_ref_each)
    if(diploid) sum_ind=sum_ind/2
    for(i in 1:sum_ind){
      matchdata=read.table(paste0('donor_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      if(!diploid){
        remove_index=i
        for(k in 2:length(n_ref_each)){
          set.seed(i*length(n_ref_each)+k)
          remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
        }
        match <- match[!match$ref_ind %in% remove_index, ]
        match$ref_ind=as.integer(factor(match$ref_ind))
        if(method=='Viterbi') rho_all[i]=est_rho_Viterbi(match,gd)
        if(method=='EM') rho_all[i]=est_rho_EM(match,gd,n_ref_each-1,ite_time,theta)
      }else{
        ## two genomes of an individual are contained
        for(w in 1:2){
          match_temp=match[which(match$mod_ind==w),]
          remove_index=2*i-2+w
          for(k in 2:length(n_ref_each)){
            set.seed((2*i-2+w)*length(n_ref_each)+k)
            remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
          }
          match_temp <- match_temp[!match_temp$ref_ind %in% remove_index, ]
          match_temp$ref_ind=as.integer(factor(match_temp$ref_ind))
          if(method=='Viterbi') rho_all[2*i-2+w]=est_rho_Viterbi(match_temp,gd)
          if(method=='EM') rho_all[2*i-2+w]=est_rho_EM(match_temp,gd,n_ref_each-1,ite_time,theta)
        }
      }
    }
  }
  
  if(matchtype=='target'){
    for(i in 1:N){
      matchdata=read.table(paste0('target_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      
      if(!diploid){
        if(method=='Viterbi') rho_all[i]=est_rho_Viterbi(match,gd)
        if(method=='EM') rho_all[i]=est_rho_EM(match,gd,n_ref_each,ite_time,theta)
      }else{
        for(w in 1:2){
          match_temp=match[which(match$mod_ind==w),]
          if(method=='Viterbi') rho_all[2*i-2+w]=est_rho_Viterbi(match_temp,gd)
          if(method=='EM') rho_all[2*i-2+w]=est_rho_EM(match_temp,gd,n_ref_each-1,ite_time,theta)
        }
      }
    }
  }
  
  if(fix_rho){
    return(mean(rho_all))
  }else{
    return(rho_all)
  }
}


est_rhoandtheta_EM <- function(match,gd,n_ref_each,ite_time=20){
  nsnp=length(gd)
  
  n_ref=sum(n_ref_each)
  
  nsnp=length(gd)
  
  theta_ite <- 0.5/sum(1/(1:n_ref))/(n_ref+1/sum(1/(1:n_ref)))
  
  rho_ite <- 400000/sum(n_ref_each)
  
  times=0
  
  while(times<=ite_time){
    
    matchmat = matchmatrix(match,n_ref,nsnp,theta_ite)
    
    unmatchmat = matchmatrix(match,n_ref,nsnp,theta=1)
    
    sameprob=cal_sameprob(nsnp,rho_ite,gd)
    
    forward = cal_forward(matchmat,nsnp,n_ref,sameprob)
    
    forward_prob = forward[[1]]
    log_multiF = forward[[2]]
    
    backward = cal_backward(matchmat,nsnp,n_ref,sameprob)
    
    backward_prob = backward[[1]]
    log_multiB = backward[[2]]
    
    
    gl <- vector()
    u <- vector()
    caltheta <- vector()
    for(j in 1:(nsnp-1)){
      gl[j]=(gd[j+1]-gd[j])
      
      al <- exp(log_multiF[j+1]+log_multiB[j+1]-log_multiF[nsnp])
      ar <- exp(log_multiF[j]+log_multiB[j+1]-log_multiF[nsnp])
      u[j] <- sum(al*forward_prob[,j+1]*backward_prob[,j+1]-
                    ar*forward_prob[,j]*backward_prob[,j+1]*matchmat[,j+1]*sameprob[j])
      
      s <- exp(log_multiF[j]+log_multiB[j]-log_multiF[nsnp])
      
      caltheta[j]=s*sum(forward_prob[,j]*backward_prob[,j]*unmatchmat[,j])
    }
    ## j=nsnp
    caltheta[nsnp] <- exp(log_multiB[nsnp])*
      sum(forward_prob[,nsnp]*backward_prob[,nsnp]*unmatchmat[,nsnp])
    
    rho_ite <- sum(u*rho_ite*gl/(1-sameprob))/sum(gl)
    theta_ite <- mean(caltheta)
    times=times+1
  }
  
  return(c(rho_ite,theta_ite))
}


est_rhoandtheta_all <- function(n_ref_each,gd,
                                matchtype='target',fix_rho=TRUE,ite_time=20,
                                N=NULL,fix_theta=TRUE,diploid=FALSE){
  rho_all=vector()
  theta_all=vector()
  if(matchtype=='donor'){
    sum_ind=sum(n_ref_each)
    if(diploid) sum_ind=sum_ind/2
    for(i in 1:sum_ind){
      
      matchdata=read.table(paste0('donor_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      ##
      if(!diploid){
        remove_index=i
        for(k in 2:length(n_ref_each)){
          set.seed(i*length(n_ref_each)+k)
          remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
        }
        match <- match[!match$ref_ind %in% remove_index, ]
        match$ref_ind=as.integer(factor(match$ref_ind))
        temp=est_rhoandtheta_EM(match,gd,n_ref_each-1,ite_time)
        rho_all[i]=temp[1]
        theta_all[i]=temp[2]
      }else{
        ## two genomes of an individual are contained
        for(w in 1:2){
          match_temp=match[which(match$mod_ind==w),]
          remove_index=2*i-2+w
          for(k in 2:length(n_ref_each)){
            set.seed((2*i-2+w)*length(n_ref_each)+k)
            remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
          }
          match_temp <- match_temp[!match_temp$ref_ind %in% remove_index, ]
          match_temp$ref_ind=as.integer(factor(match_temp$ref_ind))
          temp=est_rhoandtheta_EM(match_temp,gd,n_ref_each-1,ite_time)
          rho_all[2*i-2+w]=temp[1]
          theta_all[2*i-2+w]=temp[2]
        }
      }
      ##
    }
  }
  
  if(matchtype=='target'){
    for(i in 1:N){
      matchdata=read.table(paste0('target_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      if(!diploid){
        temp=est_rhoandtheta_EM(match,gd,n_ref_each,ite_time)
        rho_all[i]=temp[1]
        theta_all[i]=temp[2]
      }else{
        for(w in 1:2){
          match_temp=match[which(match$mod_ind==w),]
          temp=est_rhoandtheta_EM(match_temp,gd,n_ref_each,ite_time)
          rho_all[2*i-2+w]=temp[1]
          theta_all[2*i-2+w]=temp[2]
        }
      }
    }
  }
  
  if(fix_rho & fix_theta) return(c(mean(rho_all),mean(theta_all)))
  if(fix_rho & !fix_theta) return(c(mean(rho_all),theta_all))
  if(!fix_rho & fix_theta) return(c(rho_all,mean(theta_all)))
  if(!fix_rho & !fix_theta) return(c(rho_all,theta_all))
}


# a logical matrix describing whether the ith target individual match
# each reference samples at each SNP
matchmatrix <- function(match,n_ref,nsnp,theta){
  matchmat=matrix(theta,nrow=n_ref,ncol=nsnp)
  for(j in 1:nsnp){
    #data=match[which(match$mod_ind==i),]
    data=match[which(match$start<=j & match$end>=j),]
    matchmat[data$ref_ind,j]=1-theta
  }
  return(matchmat)
}

# the probability for transitting to the same state
cal_sameprob <- function(nsnp,rho,gd){
  sameprob=vector()
  for(j in 1:(nsnp-1)){
    gd_use=gd[j+1]-gd[j]
    sameprob[j]=exp(-rho*gd_use)
  }
  return(sameprob)
}

# calculate the forward probability for target individual i
cal_forward <- function(matchmat,nsnp,n_ref,sameprob){
  otherprob = (1-sameprob)/n_ref
  forward_prob <- matrix(0,nrow=n_ref,ncol=nsnp)
  ### log(1)=0
  log_multiF <- 0
  ### if no matches, the algorithm cannot continue;
  ### so we assume it's transversion or we don't have long matches including this site
  ### we turn all of them into matches to continue
  if(sum(matchmat[,1])!=0){
    forward_prob[,1] = as.numeric(matchmat[,1])/sum(matchmat[,1])
  }else{
    forward_prob[,1] = 1/n_ref
  }
  
  for(j in 2:nsnp){
    if(sum(matchmat[,j])==0){
      matchmat[,j]=1
    }
    forward_prob[,j] = matchmat[,j] * (sameprob[j-1] * forward_prob[,j-1] + otherprob[j-1])
    F_sum <- sum(forward_prob[,j])
    log_multiF <- c(log_multiF,log(F_sum)+log_multiF[j-1])
    forward_prob[,j] = forward_prob[,j]/F_sum
    
  }
  return(list(forward_prob,log_multiF))
}


# calculate the backward probability for target individual i
cal_backward <- function(matchmat,nsnp,n_ref,sameprob){
  otherprob=(1-sameprob)/n_ref
  backward_prob <- matrix(0,nrow=n_ref,ncol=nsnp)
  ## b should be all 1s at the last SNP
  ## we normalize this, and the sum is recorded in log
  log_multiB <- log(n_ref)
  backward_prob[,nsnp]=1/n_ref
  for(j in (nsnp-1):1){
    if(sum(matchmat[,j+1])==0){
      matchmat[,j+1]=1
    }
    Bjp1=matchmat[,j+1] * backward_prob[,j+1]
    backward_prob[,j] = otherprob[j] * sum(Bjp1) + sameprob[j] * Bjp1
    
    B_sum <- sum(backward_prob[,j])
    log_multiB <- c(log(B_sum)+log_multiB[1],log_multiB)
    backward_prob[,j] = backward_prob[,j]/B_sum
    
  } 
  return(list(backward_prob,log_multiB))
}

# calculate the marginal probability for each reference
cal_marginal <- function(forward_prob,backward_prob){
  marginal_prob <- forward_prob*backward_prob
  for(j in 1:ncol(marginal_prob)){
    marginal_prob[,j] = marginal_prob[,j]/sum(marginal_prob[,j])
  }
  return(marginal_prob)
}

# calculate the probability for each ancestry
cal_painting <- function(marginal_prob,n_ref_each){
  # n_ref_each is a vector representing the number of reference for each ancestry
  painting = list()
  painting[[1]] = colSums(marginal_prob[1:n_ref_each[1],])
  start=n_ref_each[1]+1
  for(k in 2:length(n_ref_each)){
    painting[[k]] = colSums(marginal_prob[start:(start+n_ref_each[k]-1),])
    start=start+n_ref_each[k]
  }
  return(painting)
}


## calculate painting for each target individual
cal_painting_each <- function(match,gd,n_ref_each,rho,theta,
                              returneachref=FALSE,donoronly=FALSE){
  n_ref=sum(n_ref_each)
  
  nsnp=length(gd)
  
  matchmat=matchmatrix(match,n_ref,nsnp,theta)
  
  sameprob=cal_sameprob(nsnp,rho,gd)
  
  forward_prob = cal_forward(matchmat,nsnp,n_ref,sameprob)[[1]]
  
  backward_prob = cal_backward(matchmat,nsnp,n_ref,sameprob)[[1]]
  
  marginal_prob = cal_marginal(forward_prob,backward_prob)
  
  if(donoronly){
    # compute the painting in the donor samples
    painting = sum(marginal_prob[1:n_ref_each[1],])/nsnp
    start=n_ref_each[1]+1
    for(k in 2:length(n_ref_each)){
      painting[k] = sum(marginal_prob[start:(start+n_ref_each[k]-1),])/nsnp
      start=start+n_ref_each[k]
    }
    return(painting)
  }else{
    if(returneachref){
      return(marginal_prob)
    }else{
      return(cal_painting(marginal_prob,n_ref_each))
    }
  }
}

## calculate the chunk length for each individual
cal_chunklength <- function(match,gd,n_ref_each,rho,theta){
  
  nsnp=length(gd)
  
  n_ref=sum(n_ref_each)
  
  matchmat=matchmatrix(match,n_ref,nsnp,theta)
  
  sameprob=cal_sameprob(nsnp,rho,gd)
  
  forward = cal_forward(matchmat,nsnp,n_ref,sameprob)
  
  forward_prob = forward[[1]]
  log_multiF = forward[[2]]
  
  backward = cal_backward(matchmat,nsnp,n_ref,sameprob)
  
  backward_prob = backward[[1]]
  log_multiB = backward[[2]]
  
  gl <- vector()
  for(j in 1:(nsnp-1)){
    gl[j]=(gd[j+1]-gd[j])
  }
  
  l=vector()
  for(i in 1:n_ref){
    l_each=vector()
    for(j in 1:(nsnp-1)){
      wl=exp(log_multiF[j]+log_multiB[j]-log_multiF[nsnp])
      wr=exp(log_multiF[j+1]+log_multiB[j+1]-log_multiF[nsnp])
      l_each[j]=0.5*(wl*forward_prob[i,j]*backward_prob[i,j]+
                       wr*forward_prob[i,j+1]*backward_prob[i,j+1])*gl[j]
    }
    l[i]=sum(l_each)
  }
  ## sum up the total length of each ancestry
  cum_sum <- c(0,cumsum(n_ref_each))
  sum_l <- vector()
  for(k in 1:length(n_ref_each)){
    sum_l <- c(sum_l,sum(l[(cum_sum[k]+1):cum_sum[k+1]]))
  }
  return(sum_l)
}




## calculate painting for all target individuals
cal_painting_all <- function(N,n_refind_each,map,method='Viterbi',fix_rho=TRUE,
                             rate=1e-8,matchtype='donor',ite_time=20,
                             theta=NULL,theta_EM=FALSE,fix_theta=TRUE,
                             diploid=FALSE){
  if(diploid){
    n_ref_each=n_refind_each*2
  }else{
    n_ref_each=n_refind_each
  }

  gd=get_gd(map,rate=rate)
  
  n_ref=sum(n_ref_each)
  
  if(!theta_EM){
    if(is.null(theta)) theta_all=0.5/sum(1/(1:n_ref))/(n_ref+1/sum(1/(1:n_ref)))
    
    if(!is.null(theta)) theta_all=theta
    
    cat('Begin estimating rho \n')
    
    rho_all = est_rho_all(n_ref_each,gd,method,matchtype=matchtype,
                          fix_rho=fix_rho,ite_time=ite_time,theta=theta_all,
                          diploid=diploid)
    
    if(fix_rho) cat('Effective population size rho is',rho_all,'\n')
    cat('Mutation rate theta is',theta_all,'\n')
    
  }else{
    cat('Begin estimating rho and theta \n')
    rhoandtheta = est_rhoandtheta_all(n_ref_each,gd,matchtype='donor',
                                      fix_rho=fix_rho,ite_time=ite_time,
                                      fix_theta=fix_theta,diploid=diploid)
    rho_all=rhoandtheta[1:length(rhoandtheta)/2]
    theta_all=rhoandtheta[-(1:length(rhoandtheta)/2)]
    if(method=='Viterbi'){
      rho_all = est_rho_all(n_ref_each,gd,method='Viterbi',matchtype=matchtype,
                            fix_rho=fix_rho,ite_time=ite_time,
                            theta=theta_all,diploid=diploid)
    }
    if(fix_rho) cat('Effective population size rho is',rho_all,'\n')
    if(fix_theta) cat('Mutation rate theta is',theta_all,'\n')
  }
  
  painting_all <- list()
  
  for(i in 1:N){
    cat('Calculating painting for target individual ',i,'\n')
    
    matchdata=read.table(paste0('target_match',i-1,'.txt'))[,c(1,3,5,6)]
    
    match=data_process(matchdata,gd)
    
    if(!diploid){
      if(fix_rho){
        rho=rho_all
      }else{
        rho=rho_all[i]
      }
      
      if(fix_theta){
        theta=theta_all
      }else{
        theta=theta_all[i]
      }
      
      painting=cal_painting_each(match,gd,n_ref_each,rho,theta=theta)
      
      if(i==1){
        painting_all=painting
      }else{
        for(j in 1:length(n_ref_each)){
          painting_all[[j]]=rbind(painting_all[[j]],painting[[j]])
        }
      }
    }else{
      
      for(w in 1:2){
        if(fix_rho){
          rho=rho_all
        }else{
          rho=rho_all[2*i-2+w]
        }
        
        if(fix_theta){
          theta=theta_all
        }else{
          theta=theta_all[2*i-2+w]
        }
        
        match_temp=match[which(match$mod_ind==w),]
        painting=cal_painting_each(match_temp,gd,n_ref_each,rho,theta=theta)
        if(i==1 & w==1){
          painting_all=painting
        }else{
          for(j in 1:length(n_ref_each)){
            painting_all[[j]]=rbind(painting_all[[j]],painting[[j]])
          }
        }
      }
    }
  
  }
  for(j in 1:length(n_ref_each)){
    colnames(painting_all[[j]])=map[,2]
    row_name <- character()
    if(!diploid){
      for(i in 1:N){
        row_name[i]=paste0('ind',i)
      }
    }else{
      for(i in 1:N){
        for(w in 1:2){
          row_name[2*i-2+w]=paste0('ind',i,'_',w)
        }
      }
    }
    rownames(painting_all[[j]])=row_name
  }
  return(painting_all)
}


cal_coancestry <- function(n_refind_each,map,method='Viterbi',fix_rho=TRUE,
                           rate=1e-8,ite_time=20,theta=NULL,theta_EM=FALSE,
                           fix_theta=TRUE,diploid=FALSE){
  
  if(diploid){
    n_ref_each=n_refind_each*2
  }else{
    n_ref_each=n_refind_each
  }
  
  gd=get_gd(map,rate=rate)
  
  n_ref=sum(n_ref_each)
  
  if(!theta_EM){
    if(is.null(theta)) theta_all=0.5/sum(1/(1:n_ref))/(n_ref+1/sum(1/(1:n_ref)))
    
    if(!is.null(theta)) theta_all=theta
    
    cat('Begin estimating rho \n')
    
    rho_all = est_rho_all(n_ref_each,gd,method,matchtype='donor',
                          fix_rho=fix_rho,ite_time=ite_time,theta=theta_all,
                          diploid=diploid)
    if(fix_rho) cat('Effective population size rho is',rho_all,'\n')
    cat('Mutation rate theta is',theta_all,'\n')
  }else{
    cat('Begin estimating rho and theta \n')
    rhoandtheta = est_rhoandtheta_all(n_ref_each,gd,matchtype='donor',
                                      fix_rho=fix_rho,ite_time=ite_time,
                                      fix_theta=fix_theta,diploid=diploid)
    rho_all=rhoandtheta[[1]]
    theta_all=rhoandtheta[[2]]
    if(method=='Viterbi'){
      rho_all = est_rho_all(n_ref_each,gd,method='Viterbi',matchtype='donor',
                            fix_rho=fix_rho,ite_time=ite_time,theta=theta_all,
                            diploid=diploid)
    }
    if(fix_rho) cat('Effective population size rho is',rho_all,'\n')
    if(fix_theta) cat('Mutation rate theta is',theta_all,'\n')
  }
  
  coa_mat_ref <- matrix(0,nrow=sum(n_ref_each),ncol=length(n_ref_each))
  
  sum_ind <- sum(n_ref_each)
  if(diploid) sum_ind=sum_ind/2
  
  for(i in 1:sum(sum_ind)){
    
    cat('Calculating chunk length for donor individual ',i,'\n')
    
    if(!diploid){
      if(fix_rho){
        rho=rho_all
      }else{
        rho=rho_all[i]
      }
      
      if(fix_theta){
        theta=theta_all
      }else{
        theta=theta_all[i]
      }
      
      matchdata=read.table(paste0('donor_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      remove_index=i
      
      for(k in 2:length(n_ref_each)){
        set.seed(i*length(n_ref_each)+k)
        remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
      }
      
      match <- match[!match$ref_ind %in% remove_index, ]
      match$ref_ind=as.integer(factor(match$ref_ind))
      
      coa_mat_ref[i,]=cal_chunklength(match,gd,n_ref_each-1,rho=rho,theta=theta)
    }else{
      ### diploid
      matchdata=read.table(paste0('donor_match',i-1,'.txt'))[,c(1,3,5,6)]
      match=data_process(matchdata,gd)
      for(w in 1:2){
        if(fix_rho){
          rho=rho_all
        }else{
          rho=rho_all[2*i-2+w]
        }
        
        if(fix_theta){
          theta=theta_all
        }else{
          theta=theta_all[2*i-2+w]
        }
        
        ##
        match_temp=match[which(match$mod_ind==w),]
        remove_index=2*i-2+w
        for(k in 2:length(n_ref_each)){
          set.seed((2*i-2+w)*length(n_ref_each)+k)
          remove_index=c(remove_index,sum(n_ref_each[1:(k-1)])+sample(1:n_ref_each[k],1))
        }
        match_temp <- match_temp[!match_temp$ref_ind %in% remove_index, ]
        match_temp$ref_ind=as.integer(factor(match_temp$ref_ind))
        
        coa_mat_ref[2*i-2+w,]=cal_chunklength(match_temp,gd,n_ref_each-1,rho=rho,theta=theta)
      }
      
    }
    
  }
  
  col_name <- character()
  for(j in 1:length(n_ref_each)){
    col_name[j]=paste0('pop',j)
  }
  
  row_name=character()
  if(!diploid){
    for(i in 1:N){
      row_name[i]=paste0('ind',i)
    }
  }else{
    for(i in 1:sum_ind){
      for(w in 1:2){
        row_name[2*i-2+w]=paste0('ref_ind',i,'_',w)
      }
    }
  }
  
  rownames(coa_mat_ref)=row_name
  colnames(coa_mat_ref)=col_name
  
  return(coa_mat_ref)
}


