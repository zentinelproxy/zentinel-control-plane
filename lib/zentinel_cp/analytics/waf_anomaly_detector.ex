defmodule ZentinelCp.Analytics.WafAnomalyDetector do
  @moduledoc """
  Pure functions for WAF anomaly detection.

  Takes baselines and current observations, returns a list of detected anomalies.
  Uses z-score analysis (sigma deviation) for statistical detection.
  """

  @default_sigma_threshold 3.0

  @doc """
  Detects anomalies by comparing observations against baselines.

  ## Parameters
    - `baselines` - map of `%{metric_type => %{mean: float, stddev: float}}`
    - `observations` - map of `%{metric_type => float}`
    - `opts` - keyword list with optional `:sigma_threshold` (default 3.0)

  ## Returns
    List of anomaly maps with type, severity, and statistical details.
  """
  def detect(baselines, observations, opts \\ []) do
    sigma_threshold = Keyword.get(opts, :sigma_threshold, @default_sigma_threshold)

    anomalies =
      Enum.flat_map(observations, fn {metric_type, observed} ->
        case Map.get(baselines, metric_type) do
          %{mean: mean, stddev: stddev}
          when is_number(mean) and is_number(stddev) and stddev > 0 ->
            detect_spike(metric_type, observed, mean, stddev, sigma_threshold)

          _ ->
            []
        end
      end)

    anomalies
  end

  @doc """
  Detects spike anomalies where the observed value exceeds mean + threshold * stddev.
  """
  def detect_spike(
        metric_type,
        observed,
        mean,
        stddev,
        sigma_threshold \\ @default_sigma_threshold
      ) do
    deviation = (observed - mean) / stddev

    if deviation > sigma_threshold do
      severity = classify_severity(deviation)

      [
        %{
          anomaly_type: "spike",
          severity: severity,
          description:
            "#{metric_type} spike: #{Float.round(observed * 1.0, 1)} observed vs #{Float.round(mean, 1)} expected (#{Float.round(deviation, 1)} sigma)",
          observed_value: observed * 1.0,
          expected_mean: mean,
          expected_stddev: stddev,
          deviation_sigma: Float.round(deviation, 2),
          evidence: %{metric_type: metric_type}
        }
      ]
    else
      []
    end
  end

  @doc """
  Detects new attack vectors (rule types not seen in baseline period).
  """
  def detect_new_vectors(known_rule_types, current_rule_types) do
    new_types = MapSet.difference(MapSet.new(current_rule_types), MapSet.new(known_rule_types))

    Enum.map(new_types, fn rule_type ->
      %{
        anomaly_type: "new_vector",
        severity: "high",
        description: "New attack vector detected: #{rule_type}",
        observed_value: 1.0,
        expected_mean: 0.0,
        expected_stddev: 0.0,
        deviation_sigma: nil,
        evidence: %{rule_type: rule_type}
      }
    end)
  end

  @doc """
  Detects IP burst anomalies (unusual number of unique attacking IPs).
  """
  def detect_ip_burst(
        unique_ips,
        baseline_mean,
        baseline_stddev,
        sigma_threshold \\ @default_sigma_threshold
      ) do
    if baseline_stddev > 0 do
      detect_spike("unique_ips", unique_ips, baseline_mean, baseline_stddev, sigma_threshold)
      |> Enum.map(&Map.put(&1, :anomaly_type, "ip_burst"))
    else
      []
    end
  end

  @doc """
  Detects rate change anomalies (sudden increase in block rate).
  """
  def detect_rate_change(
        current_rate,
        baseline_mean,
        baseline_stddev,
        sigma_threshold \\ @default_sigma_threshold
      ) do
    if baseline_stddev > 0 do
      detect_spike("block_rate", current_rate, baseline_mean, baseline_stddev, sigma_threshold)
      |> Enum.map(&Map.put(&1, :anomaly_type, "rate_change"))
    else
      []
    end
  end

  @doc """
  Classifies anomaly severity based on sigma deviation.
  """
  def classify_severity(sigma) when sigma >= 5.0, do: "critical"
  def classify_severity(sigma) when sigma >= 4.0, do: "high"
  def classify_severity(sigma) when sigma >= 3.0, do: "medium"
  def classify_severity(_), do: "low"
end
