


# ---- libs ----

library("arrow") # reading in parquet data
library("dplyr") # piping and manipulation of data
library("tibble") # prettier data.frames
library("ggplot2") # plotting
library("knitr") # to print kable(.) tables
library("tidyr") # pivot_wider() function
library("pharmsignal") # disproportionality statistics 

# ---- load ----


# read in line data using arrow::read_parquet()
# (data saved in parquet format for speed/storage size)
# takes ~ 1.5 sec on i5-8400/32GB@2133MHz(CL15)/500GB 970 EVO Plus
system.time({
  signal_data <- 
    read_parquet(
      file = "data/signal_data.parquet",
      as_data_frame = TRUE
    )
})

# check data is in tibble format
is_tibble(signal_data)
class(signal_data)
nrow(signal_data)

# data are ~500MB in memory but this call hangs
# format(object.size(signal_data), "MB") 


# ---- wrangle ----

# turn row data into summarised counts for analysis
# (NOTE: that comparator == "(1) All" is already in summarised count format
# as this would otherwise be 7,741,798 additional rows in the tibble)
signal_data <- 
  signal_data %>%
  group_by(comparator, exposure, outcome) %>%
  summarise(n = sum(record_cnt), .groups = "keep") %>%
  ungroup() %>%
  arrange(comparator, exposure, outcome) 

# have a look
signal_data %>% kable(.)

# create a,b,c,d cell counts as columns  
signal_data_wide <-
  signal_data %>%
  pivot_wider(
    names_from = c("exposure", "outcome"), 
    values_from = "n",
    names_sep = "_"
  )

# have a look
signal_data_wide

# edit exposure and outcome values for shorter expressions
# they now take form: "ExOy" = `Exposure <x> Outcome <y>` where
# <x> = "p" (positive) if exposure == "rituximab", "n" (negative) otherwise
# <y> = "p" (positive) if outcome == "PG", "n" (negative) otherwise
colnames(signal_data_wide) <- gsub("\\[rituximab\\]", "[E]", colnames(signal_data_wide))
colnames(signal_data_wide) <- gsub("\\[PG\\]", "[O]", colnames(signal_data_wide))
colnames(signal_data_wide) <- gsub("not \\[([EO])\\]", "[\\1]n", colnames(signal_data_wide))
colnames(signal_data_wide) <- gsub("\\](_|$)", "]p\\1", colnames(signal_data_wide))
# rm punctuation greedily
colnames(signal_data_wide) <- gsub("(\\[|\\]|_)", "", colnames(signal_data_wide)) 

# have a look
signal_data_wide

# ---- generate_stats ----

# calculate disproportionality statistics seen in tab 2/fig 1 in paper
signal_tab <-
  with(
    signal_data_wide, 
    bcpnn_mcmc_signal(
      a = EpOp,
      b = EpOn,
      c = EnOp,
      d = EnOn
    )
  )

# add analysis names to results
signal_tab <-
  bind_cols(
    Comparator = signal_data_wide$comparator,
    signal_tab
  )

# take from log2(ratio) scale to ratio scale
signal_tab <-
  signal_tab %>% 
  mutate(
    ci_lo     = 2^ci_lo,  
    ci_hi     = 2^ci_hi, 
    est       = 2^est, 
    est_scale = "orig scale"
  ) 

# ---- table2 -----

table2 <-
  signal_tab %>%
  rename(
    `N ritux and PG` = n11, 
    `N ritux` = `drug margin`
  ) %>%
  mutate(
    `RSIC = 2^IC` = sprintf("%3.2f (%3.2f, %3.2f)", est , ci_lo, ci_hi),
    `Significant` = (ci_lo > 1) | (ci_hi < 1),
    `Potential signal` = if_else((est > 2) & Significant, "*", ""),
    `N Comparator and PG` = `event margin` - `N ritux and PG`,
    `N Comparator` = `n..` - `N ritux`
  ) %>%
  dplyr::select(
    Comparator, 
    `N ritux and PG`, 
    `N ritux`, 
    `N Comparator and PG`, 
    `N Comparator`, 
    `RSIC = 2^IC`, 
    `Potential signal`
  )  

# print table 2
table2 %>%
  kable(.)

# ---- figure1 -----


# get min and max values for the y-axis
ymi <- min(signal_tab[["ci_lo"]])
yma <- max(signal_tab[["ci_hi"]])

# create colour palette for comparators
pal_use <- "Tableau 10" 
lvls  <- sort(unique(signal_tab[["Comparator"]]))
pal_comp <- palette.colors(n = length(lvls), palette = pal_use) 
names(pal_comp) <- lvls

# use ggplot to plot disproportionality statistics
fig1 <-
  signal_tab %>%
  ggplot(aes(x = Comparator, y = est, col = Comparator)) %+%
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0, alpha = 0.5) %+%
  geom_point(size = 2) %+%
  geom_hline(yintercept = 1) %+%
  geom_hline(yintercept = 2, linetype = 2) %+%
  scale_color_manual(values = pal_comp) %+%
  scale_y_continuous(
    trans = "log2", 
    limits = c(min(1, ymi), max(1, yma))
  ) %+%
  labs(
    x = "Comparator", 
    y = "RSIC = 2^IC estimate using BCPNN MCMC\n(ratio scale with 95% CI)", 
    col = "Comparator"
  ) %+%
  theme_bw() %+%
  theme(
    text = element_text(family = "serif"),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  ) 

# have a look
fig1

# save plot as png
ggsave(fig1, filename = "fig/fig1.png", width = 5, height = 4)




