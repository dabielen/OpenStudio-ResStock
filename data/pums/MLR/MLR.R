library(MASS)
library(ggplot2)
library(ggfortify)
library(leaps)
library(reshape2)         

# totrooms to Size
df = read.csv('../../recs/MLR/recs.csv')
df = subset(df, select=c('totrooms', 'Size', 'nweight'))
df = dcast(df, totrooms * nweight ~ Size)
df[['0-1499']] = df$nweight * df[['0-1499']]
df[['1500-2499']] = df$nweight * df[['1500-2499']]
df[['2500-3499']] = df$nweight * df[['2500-3499']]
df[['3500+']] = df$nweight * df[['3500+']]
df$nweight = NULL
attach(df)
agg = aggregate(df, by=list(totrooms), FUN=sum)
detach(df)
agg$totrooms = agg$Group.1
agg$Group.1 = NULL
map = as.data.frame(prop.table(data.matrix(subset(agg, select=c('0-1499', '1500-2499', '2500-3499', '3500+'))), 1))
map$totrooms = agg$totrooms
map

# state = 'CA'
state = 'all'

x.vars.con = c()

y.vars.con = c('hhincome')
# y.vars.con = c('fpl')

# x.vars.cat = c('heatingfuel')
x.vars.cat = c('vintage', 'rooms', 'size')
# x.vars.cat = c('vintage', 'rooms', 'heatingfuel')
# x.vars.cat = c('vintage', 'rooms', 'heatingfuel', 'bedrooms', 'hhtype', 'region', 'ownershp', 'acrehous', 'kitchen', 'plumbing', 'vehicles', 'race')

y.vars.cat = c()

df = read.csv('pums.csv')

# filters
df = df[df$hhincome>=0, ]
df = df[df$hhincome <= 250000, ]
df = df[df$nfams==1, ]

if (state != 'all'){
  df = df[df$state_abbr==state, ]
}

# add the Size column according to the map
df$size = NA

# 1: 0-1499
df[df$rooms==1, 'size'] = '0-1499'

# 2: 0-1499 (85%), 1500-2499 (15%)
num_rooms = 2
df[sample(which(df$rooms==num_rooms & is.na(df$size)), round(map[map$totrooms==num_rooms, '0-1499'] * length(which(df$rooms==num_rooms)))), 'size'] = '0-1499'
df[sample(which(df$rooms==num_rooms & is.na(df$size)), round(map[map$totrooms==num_rooms, '1500-2499'] * length(which(df$rooms==num_rooms)))), 'size'] = '1500-2499'

for (num_rooms in c(3, 4, 5, 6, 7, 8, 9)) {
  population = length(which(df$rooms==num_rooms & is.na(df$size)))
  df[sample(which(df$rooms==num_rooms & is.na(df$size)), round(map[map$totrooms==num_rooms, '0-1499'] * length(which(df$rooms==num_rooms)))), 'size'] = '0-1499'
  sampled = round(map[map$totrooms==num_rooms, '0-1499'] * length(which(df$rooms==num_rooms)))
  df[sample(which(df$rooms==num_rooms & is.na(df$size)), round(map[map$totrooms==num_rooms, '1500-2499'] * length(which(df$rooms==num_rooms)))), 'size'] = '1500-2499'
  sampled = sampled + round(map[map$totrooms==num_rooms, '1500-2499'] * length(which(df$rooms==num_rooms)))
  df[sample(which(df$rooms==num_rooms & is.na(df$size)), round(map[map$totrooms==num_rooms, '2500-3499'] * length(which(df$rooms==num_rooms)))), 'size'] = '2500-3499'
  sampled = sampled + round(map[map$totrooms==num_rooms, '2500-3499'] * length(which(df$rooms==num_rooms)))
  df[sample(which(df$rooms==num_rooms & is.na(df$size)), population - sampled), 'size'] = '3500+' # whatever's left because of rounding issues
}

df = subset(df, select=c(x.vars.con, y.vars.con, x.vars.cat, y.vars.cat, c('hhwt', 'state_abbr')))

df$values = 'actual'

df[c(x.vars.cat, y.vars.cat)] = lapply(df[c(x.vars.cat, y.vars.cat)], factor) # apply factor to each of the categorical vars
df = na.omit(df) # this removes rows with at least one NA

dep_vars = c(y.vars.con, y.vars.cat)
indep_vars = c(x.vars.con, x.vars.cat)

# FIRST PASS
attach(df)
df.lm1 = lm(paste(dep_vars, paste(indep_vars, collapse=' + '), sep=' ~ '), weights=hhwt, data=df, x=T)
detach(df)
summary(df.lm1)
write.csv(summary(df.lm1)$coefficients, 'lm1.csv') # write out first pass to csv
###

sig_indep_vars_factors = rownames(data.frame(summary(df.lm1)$coefficients)[data.frame(summary(df.lm1)$coefficients)$'Pr...t..' <= 0.5, ]) # remove insignificant vars
sig_indep_vars_factors = sig_indep_vars_factors[!sig_indep_vars_factors %in% c('(Intercept)')]
sig_indep_vars = c()
for (x in indep_vars) {
  for (y in sig_indep_vars_factors) {
    if (grepl(x, y)) {
      if (!(x %in% sig_indep_vars)) {
        sig_indep_vars = c(sig_indep_vars, x)
      }
    }
  }
}

# SECOND PASS
attach(df)
df.lm2 = lm(paste(dep_vars, paste(sig_indep_vars, collapse=' + '), sep=' ~ '), weights=hhwt, data=df, x=T)
detach(df)
summary(df.lm2)
write.csv(summary(df.lm2)$coefficients, 'lm2.csv') # write out first pass to csv
###

df2 = df
df2$values = 'predict'
df2[[y.vars.con[[1]]]] = predict(df.lm2, newdata=subset(df2, select=sig_indep_vars)) # this is the same as the fitted values

counts = c(sum(df$hhwt), sum(df2$hhwt))
labels = paste(c('actual', 'predict'), ', n = ', round(counts), sep='')

# p = ggplot(NULL, aes(x=hhincome, colour=values, weight=hhwt/sum(hhwt))) + geom_density(data=df2) + geom_density(data=df) + scale_colour_discrete(name='model', labels=labels) + xlim(0, 250000) + ylim(0, 0.000015)
p = ggplot(NULL, aes_string(x=y.vars.con[[1]], colour='values')) + geom_density(data=df2) + geom_density(data=df) + scale_colour_discrete(name='model', labels=labels)
# binwidth = 1000
# p = ggplot(NULL, aes(x=hhincome, colour=values, weight=hhwt/sum(hhwt))) + geom_histogram(data=df2, binwidth=binwidth, alpha=0.1) + geom_histogram(data=df, binwidth=binwidth, alpha=0.1) + scale_colour_discrete(name='model', labels=labels) + xlim(0, 250000) + ylim(0, 0.03)
ggsave(p, file='dist.png', width=14)

# p = ggplot(df2) + geom_point(aes(x=actual, y=hhincome), size=0.8, colour="blue") + geom_smooth(data=df2, aes(x=actual, y=hhincome), size=0.8, colour="red", se=T) + xlim(0, 250000)
# ggsave(p, file='conf.png', width=14)

p = autoplot(df.lm2, label.size=3)
ggsave(p, file='stat.png', width=14)

for (x in sig_indep_vars) {

  temp = df
  temp2 = df2

  temp = temp[temp$rooms!=1 & temp$rooms!=2, ]
  temp2 = temp2[temp2$rooms!=1 & temp2$rooms!=2, ]
  temp$rooms = factor(temp$rooms)
  temp2$rooms = factor(temp2$rooms)
  
  lvls = levels(as.factor(temp2[[x]]))
  counts = aggregate(temp2$hhwt, by=list(bin=temp2[[x]]), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')
  
  # p = ggplot(df2, aes(x=hhincome, weight=hhwt/sum(hhwt))) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels) + xlim(0, 250000) + ylim(0, 0.00002)
  # ggsave(p, file=paste(x,'png',sep='_pre.'), width=14)
  
  p = ggplot(temp2, aes_string(x=y.vars.con[[1]])) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels)
  ggsave(p, file=paste(x,'png',sep='_pre.'), width=14)  
  
  lvls = levels(as.factor(temp[[x]]))
  counts = aggregate(temp$hhwt, by=list(bin=temp[[x]]), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')
  
  # q = ggplot(df, aes(x=hhincome, weight=hhwt/sum(hhwt))) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels) + xlim(0, 250000) + ylim(0, 0.00002)
  # ggsave(q, file=paste(x,'png',sep='_act.'), width=14)
  
  q = ggplot(temp, aes_string(x=y.vars.con[[1]])) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels)
  ggsave(q, file=paste(x,'png',sep='_act.'), width=14)  
  
}

# rooms and vintage

for (vintage in levels(as.factor(df$vintage))){

  temp = df[df$vintage==vintage, ]
  temp2 = df2[df2$vintage==vintage, ]
  
  temp = temp[temp$rooms!=1 & temp$rooms!=2, ]
  temp2 = temp2[temp2$rooms!=1 & temp2$rooms!=2, ]
  
  temp$rooms_and_vintage = paste(temp$rooms, temp$vintage)
  temp2$rooms_and_vintage = paste(temp2$rooms, temp2$vintage)
      
  lvls = levels(as.factor(temp2$rooms_and_vintage))
  counts = aggregate(temp2$hhwt, by=list(bin=temp2$rooms_and_vintage), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')

  # p = ggplot(temp2, aes(x=hhincome, weight=hhwt/sum(hhwt))) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels) + xlim(0, 250000) + ylim(0, 0.000006)
  # ggsave(p, file=paste(gsub('<', '', vintage),'png',sep='_pre.'), width=14)
  
  p = ggplot(temp2, aes_string(x=y.vars.con[[1]])) + geom_density(aes(colour=rooms_and_vintage)) + scale_colour_discrete(name='rooms_and_vintage', labels=labels)
  ggsave(p, file=paste(gsub('<', '', vintage),'png',sep='_pre.'), width=14)
  
  lvls = levels(as.factor(temp$rooms_and_vintage))
  counts = aggregate(temp$hhwt, by=list(bin=temp$rooms_and_vintage), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')

  # q = ggplot(temp, aes(x=hhincome, weight=hhwt/sum(hhwt))) + geom_density(aes_string(colour=x)) + scale_colour_discrete(name=x, labels=labels) + xlim(0, 250000) + ylim(0, 0.000006)
  # ggsave(q, file=paste(gsub('<', '', vintage),'png',sep='_act.'), width=14)
  
  q = ggplot(temp, aes_string(x=y.vars.con[[1]])) + geom_density(aes(colour=rooms_and_vintage)) + scale_colour_discrete(name='rooms_and_vintage', labels=labels)
  ggsave(q, file=paste(gsub('<', '', vintage),'png',sep='_act.'), width=14)
  
}

if (state == 'all'){

  temp = df
  temp2 = df2

  temp = temp[temp$rooms!=1 & temp$rooms!=2, ]
  temp2 = temp2[temp2$rooms!=1 & temp2$rooms!=2, ]
  
  lvls = levels(as.factor(temp2$state_abbr))
  counts = aggregate(temp2$hhwt, by=list(bin=temp2$state_abbr), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')
  
  p = ggplot(temp2, aes_string(x=y.vars.con[[1]])) + geom_density(aes(colour=state_abbr)) + scale_colour_discrete(name='state_abbr', labels=labels)
  ggsave(p, file='state_pre.png', width=14)
  
  lvls = levels(as.factor(temp$state_abbr))
  counts = aggregate(temp$hhwt, by=list(bin=temp$state_abbr), FUN=sum)$x
  labels = paste(lvls, ', n = ', round(counts), sep='')
  
  q = ggplot(temp, aes_string(x=y.vars.con[[1]])) + geom_density(aes(colour=state_abbr)) + scale_colour_discrete(name='state_abbr', labels=labels)
  ggsave(q, file='state_act.png', width=14)
  
}
