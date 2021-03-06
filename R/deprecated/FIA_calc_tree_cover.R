# Code for generating % tree cover from Forest Inventory Analysis
# Date: November 11th, 2016
# Author: Kelly Heilman (kheilman@nd.edu)
# Download a state PLOT and TREE datatables. 
# initially, lets try Illinois Data: IL_plot and IL_Tree
library(sp)
library(ggplot2)
library(raster)
IL_PLOT <- read.csv( "data/IL_PLOT.csv" )
IL_TREE <- read.csv("data/IL_TREE.csv")

#add in the indiana data
IN_PLOT <- read.csv("data/IN_PLOT.csv")
IN_TREE <- read.csv("data/IN_TREE.csv")
#IL_PLOT has the fuzzed plot coordinates
#IL_TREE has the azimuth, diameter, and direction from the plot center to create the stem maps
# they can be merged based on the PLT_CN

IL_PLOT <- rbind(IL_PLOT, IN_PLOT)
IL_TREE <- rbind(IL_TREE, IN_TREE)
#before we can map each FIA stand, we need to convert the FIA lat long coordinates to great lakes albers projections (in meters)
coordinates(IL_PLOT) <- ~ LON + LAT # make this a spatial object
proj4string(IL_PLOT)<-CRS( "+proj=longlat +datum=WGS84" ) #define at the WGS84 latl
#now convert to great lakes albers
PLOT.albers <- spTransform(IL_PLOT ,CRS("+init=epsg:3175"))

PLOT.albers <- data.frame(PLOT.albers)

tree.sp <- merge(x= IL_TREE, y=PLOT.albers, by.x="PLT_CN", by.y = "CN")
#there are alot of NAs in the DIST column too, this is potentially problematic
tree.sp <- tree.sp[!is.na(tree.sp$DIST),]

feettometers <- 0.3048
# need to make sure that the distances to trees are in meters, and we calculate xy coords of each tree in the plot, based on the xy coordiantes of the plot
# and the azimuth, and distance to each tree. We also add 1/2 of the diameter (also in m) to the distance to account for the distance to center of the tree  
# r trig functions take angles in radians

as_radians<- function(deg) {(deg * pi) / (180)}

tree.sp$TreeX1 <- tree.sp$LON + cos(as_radians(tree.sp$AZIMUTH))*((tree.sp$DIST*feettometers) + (0.5*tree.sp$DIA*feettometers))
tree.sp$TreeY1 <- tree.sp$LAT + sin(as_radians(tree.sp$AZIMUTH))*((tree.sp$DIST*feettometers) + (0.5*tree.sp$DIA*feettometers))

#remove all trees with <8inches diameter
summary(tree.sp$DIA)
hist(tree.sp$DIA)
tree.sp <- tree.sp[tree.sp$DIA > 8,]
# now need to calculate a crown width for the trees in this plot
# need to match up a species code
spec.codes <- read.csv('data/FIA_conversion-SGD_remove_dups.csv', stringsAsFactor = FALSE)
spec.codes$SPCD <- spec.codes$spcd
spec.codes$Paleon <- spec.codes$PalEON

tree.sp <- merge(tree.sp, spec.codes[, c('SPCD', 'PalEON')],  by = "SPCD")

CW.table <- read.csv('data/FHM_paleon_crown_allometry_coeff.csv', 
                     stringsAsFactors=FALSE)

form <- function(x){
  
  eqn <- match(x$PalEON, CW.table[,2])
  eqn[is.na(eqn)] <- 1  #  Sets it up for non-tree.
  
  b0 <- CW.table[eqn,3]
  b1 <- CW.table[eqn,4]
  
  CW <- (b0 + b1 * (x$DIA*2.54))
  CW
}

CW <- rep(1, nrow(tree.sp))

#this function takes a really long time for all the il points, can we use an apply

for(i in 1:nrow(tree.sp)){
  CW[i] <- form(tree.sp[i,])
  cat(i,'\n')
}

summary(CW)

tree.sp$CROWNWIDTH <- CW # add the crown widths to the dataset
#for now, remove the NA values
tree.sp <- tree.sp[!is.na(tree.sp$CROWNWIDTH),]
#there are alot of NAs in the DIST column too, this is potentially problematic
tree.sp <- tree.sp[!is.na(tree.sp$DIST),]

#now we need to code which trees have crown widths that extend greater than their distance to the center point
tree.sp$coverscenter <- 0 #value if no trees cover center
tree.sp[tree.sp$CROWNWIDTH/2 < tree.sp$DIST**2.54, ]$coverscenter <- 1
#there are some trees that dont cover the center

#next, we need to provide a value per plot that indicates if we have at least 1 tree covereing the FIA plot center

agg.plot <- aggregate(tree.sp$coverscenter, by=list(Y =  tree.sp$LAT,X = tree.sp$LON), 
          FUN=sum, na.rm=TRUE)

head(agg.plot)
colnames(agg.plot) <- c('y', "x", "coverscenter")
#coordinates(agg.plot) <- ~x +y
#spplot(agg.plot, "coverscenter")
agg.plot$pctcover <-NA 
agg.plot[agg.plot$coverscenter >= 1, ]$pctcover <- 1
agg.plot[agg.plot$coverscenter <= 1, ]$pctcover <- 0
summary(agg.plot)


#okay now we need to find the proportion points covered within each paleon grid cell
# assign to paleon grid cell
base.rast <- raster(xmn = -71000, xmx = 2297000, ncols=296,
                    ymn = 58000,  ymx = 1498000, nrows = 180,
                    crs = '+init=epsg:3175')
coordinates(agg.plot)<- ~ x + y
png("outputs/pct_tree_cover_FIA.png")
hist(agg.plot$pctcover, main = "FIA % cover by plot", xlab = "% tree cover")
dev.off()
#create spatial object with agg.plot

proj4string(agg.plot)<-CRS('+init=epsg:3175')
numbered.rast <- setValues(base.rast, 1:ncell(base.rast))
numbered.cell <- extract(numbered.rast, spTransform(agg.plot,CRSobj=CRS('+init=epsg:3175')))

gridded.plot<- data.frame(xyFromCell(base.rast, numbered.cell),
                        numbered.cell, 
                       pctcover = agg.plot$pctcover, 
                          coverscenter = agg.plot$coverscenter)
gridded.plot$count <- 1
gridded.cells <- aggregate(gridded.plot$pctcover, by=list(Y =  gridded.plot$y,X = gridded.plot$x), 
                          FUN=sum, na.rm=TRUE)
gridded.count <- aggregate(gridded.plot$count, by=list(Y =  gridded.plot$y,X = gridded.plot$x), 
                           FUN=sum, na.rm=TRUE)
pdf("outputs/FIA_treecover_11.21.16.pdf")
hist(gridded.cells$x/gridded.count$x)
#okay there are alot of grid cells with only one plot per cell. We need an alternative
gridded.count$porcover <- (gridded.cells$x/gridded.count$x)*100

coordinates(gridded.count) <- ~X +Y
spplot(gridded.count, "porcover")
gridded.count <- data.frame(gridded.count)

agg.plot <- data.frame(agg.plot)
write.csv(agg.plot, "outputs/FIA_plot_agg_fuzzed_alb.csv")

write.csv(gridded.count, "outputs/FIA_plot_agg_grid_alb.csv")

#map out percent cover:
library(maps)
all_states <- map_data("state")
states <- subset(all_states, region %in% c( "illinois",  'indiana') )
coordinates(states)<-~long+lat
class(states)
proj4string(states) <-CRS("+proj=longlat +datum=NAD83")
mapdata<-spTransform(states, CRS('+init=epsg:3175'))
mapdata <- data.frame(mapdata)

#map using ggplot
ggplot(gridded.count, aes(x = X, y = Y, fill= porcover)) + geom_raster()+geom_polygon(data = mapdata, aes(group = group,x=long, y =lat, colour= 'black'), fill = NA)+theme_bw()

#map the number of fia plots per grid cell on here
ggplot(gridded.count, aes(x = X, y = Y, fill= x)) + geom_raster()+geom_polygon(data = mapdata, aes(group = group,x=long, y =lat, colour= 'black'), fill = NA)+theme_bw()

# if all the plots are 24 ft fixed radius macroplots (DESIGNCD==1) (we know there are some other designs)
# we can calculate % cover differently:

plotarea.ft <- pi*24

# calculate the crown area from crown width
tree.sp$crownarea <- pi*((tree.sp$CROWNWIDTH/2)*2.54)

# only look a the cover of dominant trees. Otherwise we get crazy total crown areas per plot
dom.codom <- tree.sp[tree.sp$CCLCD == 2, ]

# add up all the crown areas by plot
CA.plot <- aggregate(dom.codom$crownarea, by=list(Y =  dom.codom$LAT,X = dom.codom$LON), 
                      FUN=sum, na.rm=TRUE)
CA.plot$pctcover <- (CA.plot$x/plotarea.ft)*100
hist(CA.plot$pctcover)

#need to fix the color of polygon so they will both plot together
ggplot(CA.plot, aes(x = X, y = Y)) + geom_point(aes(colour= pctcover))#+#scale_color_gradient(low="blue", high="red")+
   #geom_polygon(data = mapdata, aes(group = group,x=long, y =lat, colour= 'black'), fill = NA)+theme_bw()


one <- tree.sp[tree.sp$SUBP == 1, ]
two<- tree.sp[tree.sp$SUBP == 2, ]
three<- tree.sp[tree.sp$SUBP == 3, ]
four<- tree.sp[tree.sp$SUBP == 4, ]
##############
#do the same for dominant and co-dominant trees
# only look a the cover of dominant trees. Otherwise we get crazy total crown areas per plot
dom.codom <- tree.sp[tree.sp$CCLCD == 2|3, ]

# add up all the crown areas by plot
CA.plot <- aggregate(dom.codom$crownarea, by=list(Y =  dom.codom$LAT,X = dom.codom$LON), 
                     FUN=sum, na.rm=TRUE)
CA.plot$pctcover <- (CA.plot$x/plotarea.ft)*100
hist(CA.plot$pctcover, breaks = 50)

#need to fix the color of polygon so they will both plot together
ggplot(CA.plot, aes(x = X, y = Y)) + geom_point(aes(colour= pctcover))#+#scale_color_gradient(low="blue", high="red")+
#geom_polygon(data = mapdata, aes(group = group,x=long, y =lat, colour= 'black'), fill = NA)+theme_bw()

dev.off()
