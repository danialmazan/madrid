source(file.path("scripts", "R", "common.R"))

# The published open-ended category must contribute to totals and the 65+ band.
ages <- parse_padron_age(c("17", "65", "100 o +", " 99 "))
residents <- c(10, 20, 7, 3)
stopifnot(identical(ages, c(17L, 65L, 100L, 99L)))
stopifnot(sum(residents) == 40, sum(residents[ages >= 65]) == 30)
stopifnot(inherits(tryCatch(parse_padron_age("unknown"), error = identity), "error"))
stopifnot(identical(parse_padron_age(c("101", "144")), c(101L, 144L)))
stopifnot(inherits(tryCatch(parse_padron_age("-1"), error = identity), "error"))
message("Population age regression checks passed")
