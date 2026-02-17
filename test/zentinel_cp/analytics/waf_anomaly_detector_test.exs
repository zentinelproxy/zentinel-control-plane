defmodule ZentinelCp.Analytics.WafAnomalyDetectorTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Analytics.WafAnomalyDetector

  describe "detect/3" do
    test "detects spike when value exceeds 3 sigma" do
      baselines = %{
        "total_blocks" => %{mean: 10.0, stddev: 2.0}
      }

      observations = %{
        "total_blocks" => 20.0
      }

      anomalies = WafAnomalyDetector.detect(baselines, observations)
      assert length(anomalies) == 1
      assert hd(anomalies).anomaly_type == "spike"
      assert hd(anomalies).deviation_sigma == 5.0
    end

    test "no anomaly when value is within normal range" do
      baselines = %{
        "total_blocks" => %{mean: 10.0, stddev: 2.0}
      }

      observations = %{
        "total_blocks" => 14.0
      }

      anomalies = WafAnomalyDetector.detect(baselines, observations)
      assert anomalies == []
    end

    test "skips metrics without baselines" do
      baselines = %{}

      observations = %{
        "total_blocks" => 100.0
      }

      anomalies = WafAnomalyDetector.detect(baselines, observations)
      assert anomalies == []
    end

    test "skips baselines with zero stddev" do
      baselines = %{
        "total_blocks" => %{mean: 10.0, stddev: 0.0}
      }

      observations = %{
        "total_blocks" => 100.0
      }

      anomalies = WafAnomalyDetector.detect(baselines, observations)
      assert anomalies == []
    end

    test "supports custom sigma threshold" do
      baselines = %{
        "total_blocks" => %{mean: 10.0, stddev: 2.0}
      }

      # Value is 2 sigma above mean
      observations = %{
        "total_blocks" => 14.0
      }

      # Default threshold (3.0) - no anomaly
      assert WafAnomalyDetector.detect(baselines, observations) == []

      # Lower threshold (1.5) - detected
      anomalies = WafAnomalyDetector.detect(baselines, observations, sigma_threshold: 1.5)
      assert length(anomalies) == 1
    end
  end

  describe "detect_spike/5" do
    test "returns spike anomaly" do
      result = WafAnomalyDetector.detect_spike("total_blocks", 25.0, 10.0, 3.0)
      assert length(result) == 1

      anomaly = hd(result)
      assert anomaly.anomaly_type == "spike"
      assert anomaly.observed_value == 25.0
      assert anomaly.expected_mean == 10.0
      assert anomaly.expected_stddev == 3.0
      assert anomaly.deviation_sigma == 5.0
    end

    test "returns empty for normal values" do
      assert WafAnomalyDetector.detect_spike("total_blocks", 12.0, 10.0, 3.0) == []
    end
  end

  describe "detect_new_vectors/2" do
    test "detects new rule types" do
      known = ["sqli", "xss"]
      current = ["sqli", "xss", "rce", "scanner"]

      anomalies = WafAnomalyDetector.detect_new_vectors(known, current)
      assert length(anomalies) == 2
      types = Enum.map(anomalies, & &1.evidence.rule_type) |> Enum.sort()
      assert types == ["rce", "scanner"]
    end

    test "returns empty when no new vectors" do
      known = ["sqli", "xss"]
      current = ["sqli"]

      assert WafAnomalyDetector.detect_new_vectors(known, current) == []
    end
  end

  describe "detect_ip_burst/4" do
    test "detects IP burst" do
      result = WafAnomalyDetector.detect_ip_burst(50.0, 10.0, 5.0)
      assert length(result) == 1
      assert hd(result).anomaly_type == "ip_burst"
    end

    test "no detection with zero stddev" do
      assert WafAnomalyDetector.detect_ip_burst(50.0, 10.0, 0.0) == []
    end
  end

  describe "detect_rate_change/4" do
    test "detects rate change" do
      result = WafAnomalyDetector.detect_rate_change(90.0, 30.0, 10.0)
      assert length(result) == 1
      assert hd(result).anomaly_type == "rate_change"
    end
  end

  describe "classify_severity/1" do
    test "classifies based on sigma" do
      assert WafAnomalyDetector.classify_severity(6.0) == "critical"
      assert WafAnomalyDetector.classify_severity(5.0) == "critical"
      assert WafAnomalyDetector.classify_severity(4.5) == "high"
      assert WafAnomalyDetector.classify_severity(4.0) == "high"
      assert WafAnomalyDetector.classify_severity(3.5) == "medium"
      assert WafAnomalyDetector.classify_severity(3.0) == "medium"
      assert WafAnomalyDetector.classify_severity(2.0) == "low"
    end
  end
end
