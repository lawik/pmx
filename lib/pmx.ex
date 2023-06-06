defmodule Pmx do
  require Logger

  def load_package!(path, to_dir) do
    path
    |> to_lock_path()
    |> File.read!()
    |> Jason.decode!()
    |> install!(to_dir)
  end

  def install!(lock, to_dir) do
    tmp_dir = System.tmp_dir!()

    lock["dependencies"]
    |> Task.async_stream(fn dep ->
      dep
      |> Pmx.Dep.new()
      |> then(fn dep ->
        # Logger.debug("Installing: #{dep.package} @ #{dep.version}")
        # IO.inspect(dep)
        dep
      end)
      |> download!(tmp_dir)
      |> verify!()
      |> extract!(to_dir)
      |> warn_about_scripts!()
    end)
    |> Enum.to_list()
  end

  defp download!(dep, tmp_dir) do
    to_path = Path.join(tmp_dir, dep.filename)
    Req.get!(dep.resolved, output: to_path)
    %{dep | local_file: to_path}
  end

  defp verify!(dep) do
    [algo_string, hash] = String.split(dep.integrity, "-", parts: 2)

    {algo, encoder} =
      case String.to_existing_atom(algo_string) do
        :sha1 -> {:sha, &Base.encode64/1}
        other -> {other, &Base.encode64/1}
      end

    calculated_hash =
      dep.local_file
      |> File.stream!([], 2048)
      |> Enum.reduce(:crypto.hash_init(algo), fn line, acc -> :crypto.hash_update(acc, line) end)
      |> :crypto.hash_final()
      |> encoder.()

    ^calculated_hash = hash
    %{dep | valid?: true}
  end

  defp to_lock_path(path) do
    if String.ends_with?(path, "package-lock.json") do
      path
    else
      Path.join(path, "package-lock.json")
    end
  end

  def extract!(dep, to_dir) do
    package_path = Path.join(to_dir, dep.package)
    extract_tar!(dep.local_file, package_path)
    %{dep | installed_path: package_path}
  end

  def extract_tar!(filepath, target_dir) do
    File.mkdir_p!(target_dir)

    with {:ok, files} <- :erl_tar.extract(filepath, [:memory, :compressed]) do
      files
      |> Task.async_stream(fn {filename, content} ->
        filename = to_string(filename)

        filename =
          if String.starts_with?(filename, "package/") do
            "package/" <> rest = filename
            rest
          else
            filename
          end

        filepath = Path.join(target_dir, filename)
        dirpath = Path.dirname(filepath)
        File.mkdir_p!(dirpath)
        File.write!(filepath, content)
      end)
      |> Stream.run()
    end
  end

  def warn_about_scripts!(dep) do
    case File.read(Path.join(dep.installed_path, "package.json")) do
      {:ok, contents} ->
        package = Jason.decode!(contents)

        Enum.each(Map.get(package, "scripts", []), fn {phase, script} ->
          if relevant_script?(phase) do
            Logger.warn(
              "Package '#{dep.package}' would have wanted to run a '#{phase}' script: #{script}"
            )
          end
        end)

      _ ->
        dep
    end
  end

  @installtime ["install", "prepare", "publish"]
  defp relevant_script?(phase) do
    Enum.any?(@installtime, fn relevant ->
      String.ends_with?(phase, relevant)
    end)
  end
end
