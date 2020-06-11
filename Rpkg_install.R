#!/usr/bin/env R

pkgs <- read.csv('rpkgs.csv', header=TRUE);
pkgvec <- as.vector(pkgs$Package);
install.packages(c(pkgvec), quiet = TRUE, keep_outputs=FALSE, dependencies = c("Depends", "Imports", "LinkingTo"), lib=Sys.getenv("R_LIBS_USER", unset=NA));
