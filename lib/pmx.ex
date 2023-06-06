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
    |> IO.inspect()
    |> Task.async_stream(fn dep ->
      dep
      |> Pmx.Dep.new()
      |> then(fn dep ->
        Logger.info("Dependency: #{dep.package} @ #{dep.version}")
        IO.inspect(dep)
        dep
      end)
      |> download!(tmp_dir)
      |> verify!()
      |> extract!(to_dir)
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

    IO.inspect(algo)

    calculated_hash =
      dep.local_file
      |> File.stream!([], 2048)
      |> Enum.reduce(:crypto.hash_init(algo), fn line, acc -> :crypto.hash_update(acc, line) end)
      |> :crypto.hash_final()
      |> encoder.()

    IO.inspect({calculated_hash, hash})

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
        filepath = Path.join(target_dir, filename)
        dirpath = Path.dirname(filepath)
        File.mkdir_p!(dirpath)
        File.write!(filepath, content)
      end)
      |> Stream.run()
    end
  end
end
