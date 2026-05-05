library(tidyverse)
library(nflreadr)
library(ggplot2)
library(broom)

# Load play by play data for 2018-2024
# This gives us enough seasons for meaningful multi-year analysis
pbp <- load_pbp(2018:2024)

# Quick check
dim(pbp)
names(pbp) %>% head(30)

# Find relevant columns
names(pbp)[grep("epa|pressure|qb_hit|sack|time_to_throw|passer", 
                names(pbp), ignore.case = TRUE)]

# Filter to passing plays, regular season only
pass_plays <- pbp %>%
  filter(
    season_type == "REG",
    play_type == "pass",
    !is.na(passer_player_name),
    !is.na(qb_epa)
  )

# Build season level stats per QB
qb_seasons <- pass_plays %>%
  group_by(passer_player_name, passer_id, season, posteam) %>%
  summarise(
    dropbacks = n(),
    epa_per_play = mean(qb_epa, na.rm = TRUE),
    sack_rate = mean(sack, na.rm = TRUE),
    qb_hit_rate = mean(qb_hit, na.rm = TRUE),
    pressure_rate = mean(qb_hit | sack, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(dropbacks >= 200)

dim(qb_seasons)
head(qb_seasons)

# Core correlation - pressure rate vs EPA per play
cor_test <- cor.test(qb_seasons$pressure_rate, qb_seasons$epa_per_play)
print(cor_test)

# Scatter plot - pressure rate vs EPA per play
ggplot(qb_seasons, aes(x = pressure_rate, y = epa_per_play)) +
  geom_point(alpha = 0.4, color = "#1a1a2e", size = 2) +
  geom_smooth(method = "lm", color = "#D4500A", se = TRUE) +
  geom_hline(yintercept = 0, linetype = "dashed", alpha = 0.4) +
  
  # Label notable QBs
  geom_text(
    data = qb_seasons %>% filter(
      epa_per_play > 0.25 | 
        epa_per_play < -0.2 |
        (pressure_rate > 0.18 & epa_per_play > 0.1)
    ),
    aes(label = paste0(passer_player_name, " ", season)),
    size = 2.5, hjust = -0.1, alpha = 0.8
  ) +
  
  labs(
    title = "Does Offensive Line Play Determine QB Success?",
    subtitle = "QB EPA/Play vs Pressure Rate Allowed (2018-2024, min. 200 dropbacks)",
    x = "Pressure Rate (QB Hit + Sack Rate)",
    y = "EPA Per Play",
    caption = "Data: nflverse | Pressure = QB hit or sack on dropback"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10, color = "gray50"),
    plot.caption = element_text(size = 8, color = "gray60")
  )

# Build career averages to identify consistent over and underperformers
qb_career <- qb_seasons %>%
  group_by(passer_player_name) %>%
  summarise(
    seasons = n(),
    avg_epa = mean(epa_per_play),
    avg_pressure = mean(pressure_rate),
    total_dropbacks = sum(dropbacks),
    .groups = "drop"
  ) %>%
  filter(seasons >= 3)  # need at least 3 seasons for consistency

# Fit linear model to get residuals
model <- lm(epa_per_play ~ pressure_rate, data = qb_seasons)

# Add residuals to season data
qb_seasons <- qb_seasons %>%
  mutate(residual = residuals(model))

# Career average residual per QB
qb_residuals <- qb_seasons %>%
  group_by(passer_player_name) %>%
  summarise(
    seasons = n(),
    avg_residual = mean(residual),
    avg_pressure = mean(pressure_rate),
    avg_epa = mean(epa_per_play),
    .groups = "drop"
  ) %>%
  filter(seasons >= 3) %>%
  arrange(desc(avg_residual))

print(qb_residuals, n = 30)

# Bar chart of top and bottom OL outperformers
top_bottom <- bind_rows(
  qb_residuals %>% slice_max(avg_residual, n = 12),
  qb_residuals %>% slice_min(avg_residual, n = 8)
) %>%
  mutate(
    direction = ifelse(avg_residual > 0, "Outperforms OL", "Underperforms OL"),
    passer_player_name = fct_reorder(passer_player_name, avg_residual)
  )

ggplot(top_bottom, aes(x = passer_player_name, y = avg_residual, fill = direction)) +
  geom_col() +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  scale_fill_manual(values = c("Outperforms OL" = "#D4500A", 
                               "Underperforms OL" = "#1a1a2e")) +
  coord_flip() +
  labs(
    title = "Which QBs Overcome Their Offensive Line?",
    subtitle = "Average EPA residual vs expected given pressure rate (2018-2024, min. 3 seasons)",
    x = NULL,
    y = "EPA Residual (positive = outperforms OL situation)",
    fill = NULL,
    caption = "Data: nflverse"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10, color = "gray50"),
    legend.position = "bottom",
    plot.caption = element_text(size = 8, color = "gray60")
  )

# Identify QBs in their first two NFL seasons
qb_seasons <- qb_seasons %>%
  group_by(passer_player_name) %>%
  mutate(nfl_year = rank(season)) %>%
  ungroup()

young_qbs <- qb_seasons %>%
  filter(nfl_year <= 2) %>%
  mutate(label = paste0(passer_player_name, "\n", season))

ggplot(young_qbs, aes(x = pressure_rate, y = epa_per_play)) +
  geom_point(aes(color = nfl_year == 1), size = 3, alpha = 0.7) +
  geom_smooth(method = "lm", color = "#D4500A", se = TRUE) +
  geom_hline(yintercept = 0, linetype = "dashed", alpha = 0.4) +
  geom_text(
    data = young_qbs %>% filter(
      epa_per_play > 0.1 | 
        epa_per_play < -0.15 |
        pressure_rate > 0.22
    ),
    aes(label = label), size = 2.5, hjust = -0.1
  ) +
  scale_color_manual(
    values = c("TRUE" = "#D4500A", "FALSE" = "#1a1a2e"),
    labels = c("TRUE" = "Year 1", "FALSE" = "Year 2")
  ) +
  labs(
    title = "OL Protection and Young QB Development",
    subtitle = "EPA/Play vs Pressure Rate for QBs in Years 1-2 (2018-2024)",
    x = "Pressure Rate",
    y = "EPA Per Play",
    color = NULL,
    caption = "Data: nflverse | Orange = Year 1, Dark = Year 2"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10, color = "gray50"),
    legend.position = "bottom",
    plot.caption = element_text(size = 8, color = "gray60")
  )

# Correlation for young QBs specifically
young_cor <- cor.test(young_qbs$pressure_rate, young_qbs$epa_per_play)
print(young_cor)

# Compare to overall correlation
cat("\nOverall dataset correlation:", round(cor(qb_seasons$pressure_rate, qb_seasons$epa_per_play), 3))
cat("\nYoung QB correlation:", round(young_cor$estimate, 3))
cat("\nDifference:", round(young_cor$estimate - cor(qb_seasons$pressure_rate, qb_seasons$epa_per_play), 3))