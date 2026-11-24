defmodule PulumiViewer.CloudFormation.Client do
  @moduledoc """
  Read-only CloudFormation Query API calls through ExAws. It calls only `List*`,
  `Describe*` and `GetTemplate`. Responses are cached for 60 s and throttled calls
  are retried with exponential backoff.
  """
  require Record
  alias PulumiViewer.AwsCredentials
  alias PulumiViewer.CloudFormation.{Cache, Error}

  Record.defrecordp(
    :el,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(:txt, :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @read_only ~w(ListStacks DescribeStacks ListStackResources DescribeStackEvents GetTemplate)
  @live_statuses ~w(CREATE_IN_PROGRESS CREATE_FAILED CREATE_COMPLETE ROLLBACK_IN_PROGRESS ROLLBACK_FAILED
    ROLLBACK_COMPLETE DELETE_IN_PROGRESS DELETE_FAILED UPDATE_IN_PROGRESS
    UPDATE_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_COMPLETE UPDATE_FAILED UPDATE_ROLLBACK_IN_PROGRESS
    UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE
    REVIEW_IN_PROGRESS IMPORT_IN_PROGRESS IMPORT_COMPLETE IMPORT_ROLLBACK_IN_PROGRESS
    IMPORT_ROLLBACK_FAILED IMPORT_ROLLBACK_COMPLETE)
  @max_attempts 6

  def list_stacks(src) do
    filter =
      @live_statuses
      |> Enum.with_index(1)
      |> Map.new(fn {s, i} -> {"StackStatusFilter.member.#{i}", s} end)

    paginate(src, "ListStacks", filter, "StackSummaries", 20)
  end

  def describe_stack(src, name) do
    with {:ok, %{"Stacks" => [stack | _]}} <-
           call(src, "DescribeStacks", %{"StackName" => name}),
         do: {:ok, stack}
  end

  def list_stack_resources(src, name),
    do: paginate(src, "ListStackResources", %{"StackName" => name}, "StackResourceSummaries", 20)

  def describe_stack_events(src, name, max_pages \\ 5),
    do: paginate(src, "DescribeStackEvents", %{"StackName" => name}, "StackEvents", max_pages)

  def get_template(src, name) do
    with {:ok, %{"TemplateBody" => body}} <-
           call(src, "GetTemplate", %{"StackName" => name, "TemplateStage" => "Original"}),
         do: {:ok, body}
  end

  defp paginate(src, action, params, key, max_pages, token \\ nil, acc \\ [])

  defp paginate(_src, _action, _params, _key, 0, _token, acc), do: {:ok, acc}

  defp paginate(src, action, params, key, pages, token, acc) do
    params = if token, do: Map.put(params, "NextToken", token), else: params

    with {:ok, result} <- call(src, action, params) do
      acc = acc ++ list(result[key])

      case result["NextToken"] do
        t when t in [nil, ""] -> {:ok, acc}
        t -> paginate(src, action, params, key, pages - 1, t, acc)
      end
    end
  end

  defp list(l) when is_list(l), do: l
  defp list(_), do: []

  @doc "One cached, retried call. Returns the `<Action>Result` element as maps and lists."
  # `src` is a source config: `%{region, name, profile}`. The name keys the cache, because two
  # sources can read the same region with different credentials.
  def call(src, action, params) when action in @read_only do
    key = {src[:name], src.region, src[:profile], action, params}
    Cache.fetch(key, fn -> attempt(src, action, params, 1) end)
  end

  defp attempt(src, action, params, n) do
    extra = Application.get_env(:pulumi_viewer, :cloudformation_aws_opts, [])

    case credentials(src[:profile]) do
      {:ok, creds} ->
        opts = creds ++ extra

        if creds != [] or extra[:access_key_id] != nil or credential_source() != :none,
          do: send_request(src, action, params, opts, n),
          else: {:error, Error.from(:no_credentials)}

      {:error, %Error{} = e} ->
        {:error, e}

      {:error, e} ->
        {:error, Error.from(e)}
    end
  end

  # A source with `?profile=` uses only that profile (never another account's keys).
  defp credentials(profile) when is_binary(profile), do: AwsCredentials.opts(profile)

  defp credentials(nil) do
    case env_credentials() do
      {:error, _} = e -> e
      creds -> {:ok, creds}
    end
  end

  defp send_request(src, action, params, opts, n) do
    op = %ExAws.Operation.Query{
      path: "/",
      service: :cloudformation,
      action: action,
      params: Map.merge(params, %{"Action" => action, "Version" => "2010-05-15"})
    }

    case request(
           op,
           Keyword.merge([region: src.region, retries: [max_attempts: 1]], Keyword.new(opts))
         ) do
      {:ok, %{body: xml}} ->
        {:ok, xml |> to_term() |> Map.get(action <> "Result", %{})}

      {:error, {:http_error, status, resp} = e} when n < @max_attempts ->
        if status == 429 or status >= 500 or
             Error.code(body(resp)) in ["Throttling", "ThrottlingException"] do
          Process.sleep(backoff(n))
          attempt(src, action, params, n + 1)
        else
          {:error, Error.from(e)}
        end

      {:error, e} ->
        {:error, Error.from(e)}
    end
  end

  # ExAws can raise or exit (for example in its AuthCache); keep it this source's error.
  defp request(op, opts) do
    ExAws.request(op, opts)
  rescue
    e -> {:error, {:raised, Exception.message(e)}}
  catch
    :exit, reason -> {:error, {:raised, inspect(reason)}}
  end

  defp body(%{body: b}), do: b
  defp body(b), do: b

  defp backoff(n), do: min(round(:math.pow(2, n) * 100) + :rand.uniform(100), 5_000)

  @doc """
  Where the credentials come from: keys in the environment, an `AWS_PROFILE` from the shared
  config (also AWS SSO, refreshed from the token cache), a host credential helper
  (`:container_full_uri`, refreshed before `Expiration`), an ECS container role, or none.
  """
  def credential_source do
    cond do
      present?("AWS_ACCESS_KEY_ID") ->
        :env

      PulumiViewer.HostCredentials.configured?() ->
        :container_full_uri

      present?("AWS_PROFILE") ->
        {:profile, System.get_env("AWS_PROFILE")}

      present?("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") ->
        :container

      present?("AWS_CONTAINER_CREDENTIALS_FULL_URI") ->
        :container

      true ->
        :none
    end
  end

  defp present?(var), do: System.get_env(var) not in [nil, ""]

  # Keys from the environment or a profile, without the instance-role fallback.
  defp env_credentials do
    case credential_source() do
      :env ->
        [
          access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
          secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
          security_token: System.get_env("AWS_SESSION_TOKEN")
        ]

      :container_full_uri ->
        case PulumiViewer.HostCredentials.fetch() do
          {:ok, keys} -> keys
          error -> error
        end

      # config/runtime.exs reads AWS_PROFILE through ExAws's :awscli source (refreshed every 30 s);
      # per-request overrides cannot carry it.
      _ ->
        []
    end
  end

  @doc false
  # Query API XML -> maps; an element whose children are all <member> becomes a list.
  def to_term(xml) when is_binary(xml) do
    {doc, _} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)

    xml_node(doc)
  end

  defp xml_node(e) do
    children = Enum.filter(el(e, :content), &Record.is_record(&1, :xmlElement))

    cond do
      children == [] ->
        el(e, :content)
        |> Enum.filter(&Record.is_record(&1, :xmlText))
        |> Enum.map_join(&IO.chardata_to_string(txt(&1, :value)))

      Enum.all?(children, &(el(&1, :name) == :member)) ->
        Enum.map(children, &xml_node/1)

      true ->
        Map.new(children, &{to_string(el(&1, :name)), xml_node(&1)})
    end
  end
end
