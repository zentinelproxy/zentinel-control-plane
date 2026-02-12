defmodule SentinelCp.Bundles.DiffTest do
  use SentinelCp.DataCase

  alias SentinelCp.Bundles.Diff

  defp bundle(config, manifest \\ %{}) do
    %{config_source: config, manifest: manifest}
  end

  describe "config_diff/2" do
    test "returns eq for identical configs" do
      a = bundle("line1\nline2")
      b = bundle("line1\nline2")
      diff = Diff.config_diff(a, b)
      assert diff == [eq: ["line1", "line2"]]
    end

    test "detects additions" do
      a = bundle("line1")
      b = bundle("line1\nline2")
      diff = Diff.config_diff(a, b)
      assert {:ins, ["line2"]} in diff
    end

    test "detects deletions" do
      a = bundle("line1\nline2")
      b = bundle("line1")
      diff = Diff.config_diff(a, b)
      assert {:del, ["line2"]} in diff
    end

    test "handles empty configs" do
      a = bundle("")
      b = bundle("new content")
      diff = Diff.config_diff(a, b)
      assert length(diff) > 0
    end
  end

  describe "annotate_diff/1" do
    test "annotates with line numbers" do
      diff = [eq: ["a"], del: ["b"], ins: ["c", "d"]]
      lines = Diff.annotate_diff(diff)

      assert [
               %{type: :eq, line: "a", number_a: 1, number_b: 1},
               %{type: :del, line: "b", number_a: 2, number_b: nil},
               %{type: :ins, line: "c", number_a: nil, number_b: 2},
               %{type: :ins, line: "d", number_a: nil, number_b: 3}
             ] = lines
    end
  end

  describe "diff_stats/1" do
    test "counts additions, deletions, unchanged" do
      diff = [eq: ["a", "b"], del: ["c"], ins: ["d", "e", "f"]]
      stats = Diff.diff_stats(diff)

      assert stats.unchanged == 2
      assert stats.deletions == 1
      assert stats.additions == 3
    end
  end

  describe "manifest_diff/2" do
    test "detects added files" do
      a = bundle("", %{"files" => %{"a.txt" => "abc"}})
      b = bundle("", %{"files" => %{"a.txt" => "abc", "b.txt" => "def"}})
      diff = Diff.manifest_diff(a, b)

      assert diff.added == ["b.txt"]
      assert diff.removed == []
      assert diff.modified == []
    end

    test "detects removed files" do
      a = bundle("", %{"files" => %{"a.txt" => "abc", "b.txt" => "def"}})
      b = bundle("", %{"files" => %{"a.txt" => "abc"}})
      diff = Diff.manifest_diff(a, b)

      assert diff.removed == ["b.txt"]
    end

    test "detects modified files" do
      a = bundle("", %{"files" => %{"a.txt" => "v1"}})
      b = bundle("", %{"files" => %{"a.txt" => "v2"}})
      diff = Diff.manifest_diff(a, b)

      assert diff.modified == ["a.txt"]
    end

    test "handles nil manifests" do
      a = bundle("", nil)
      b = bundle("", nil)
      diff = Diff.manifest_diff(a, b)

      assert diff.added == []
      assert diff.removed == []
      assert diff.modified == []
    end
  end

  describe "semantic_diff/2" do
    test "detects added services" do
      a = bundle(~s(route "api" {\n}\n))
      b = bundle(~s(route "api" {\n}\nroute "web" {\n}\n))

      result = Diff.semantic_diff(a, b)
      assert "web" in result.services_added
      assert result.services_removed == []
    end

    test "detects removed services" do
      a = bundle(~s(route "api" {\n}\nroute "web" {\n}\n))
      b = bundle(~s(route "api" {\n}\n))

      result = Diff.semantic_diff(a, b)
      assert "web" in result.services_removed
      assert result.services_added == []
    end

    test "detects settings changes" do
      a = bundle("settings {\n  timeout 30\n}\n")
      b = bundle("settings {\n  timeout 60\n}\n")

      result = Diff.semantic_diff(a, b)
      assert result.settings_changed == true
    end

    test "handles no changes" do
      config = ~s(route "api" {\n}\n)
      a = bundle(config)
      b = bundle(config)

      result = Diff.semantic_diff(a, b)
      assert result.services_added == []
      assert result.services_removed == []
      assert result.services_modified == []
      assert result.settings_changed == false
    end
  end

  describe "side_by_side_diff/1" do
    test "pairs equal lines on both sides" do
      lines = [%{type: :eq, line: "a", number_a: 1, number_b: 1}]
      pairs = Diff.side_by_side_diff(lines)

      assert length(pairs) == 1
      assert hd(pairs).left == hd(lines)
      assert hd(pairs).right == hd(lines)
    end

    test "pairs del with ins" do
      lines = [
        %{type: :del, line: "old", number_a: 1, number_b: nil},
        %{type: :ins, line: "new", number_a: nil, number_b: 1}
      ]

      pairs = Diff.side_by_side_diff(lines)
      assert length(pairs) == 1
      assert hd(pairs).left.line == "old"
      assert hd(pairs).right.line == "new"
    end

    test "handles unpaired deletion" do
      lines = [
        %{type: :del, line: "removed", number_a: 1, number_b: nil},
        %{type: :eq, line: "same", number_a: 2, number_b: 1}
      ]

      pairs = Diff.side_by_side_diff(lines)
      assert length(pairs) == 2
      assert Enum.at(pairs, 0).left.line == "removed"
      assert Enum.at(pairs, 0).right == nil
      assert Enum.at(pairs, 1).left.line == "same"
    end

    test "handles unpaired insertion" do
      lines = [%{type: :ins, line: "added", number_a: nil, number_b: 1}]

      pairs = Diff.side_by_side_diff(lines)
      assert length(pairs) == 1
      assert hd(pairs).left == nil
      assert hd(pairs).right.line == "added"
    end

    test "handles empty input" do
      assert Diff.side_by_side_diff([]) == []
    end
  end
end
