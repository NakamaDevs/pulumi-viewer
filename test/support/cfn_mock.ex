defmodule PulumiViewer.CfnMock do
  @moduledoc "ExAws HTTP client that answers CloudFormation Query calls from canned XML."
  @behaviour ExAws.Request.HttpClient

  @ns ~s(xmlns="http://cloudformation.amazonaws.com/doc/2010-05-15/")

  defp access_key(headers) do
    auth =
      Enum.find_value(headers, "", fn {k, v} -> String.downcase(k) == "authorization" && v end)

    case Regex.run(~r/Credential=([^\/]+)\//, auth) do
      [_, key] -> key
      _ -> nil
    end
  end

  @impl true
  def request(:post, _url, body, headers, _opts) do
    params = URI.decode_query(body)

    # a test can ask to see which access key signed each call
    case :persistent_term.get({__MODULE__, :report_to}, nil) do
      nil -> :ok
      pid -> send(pid, {:cfn_key, access_key(headers), params["Action"]})
    end

    case :persistent_term.get({__MODULE__, :calls}, nil) do
      nil -> :ok
      c -> :counters.add(c, 1, 1)
    end

    case :persistent_term.get({__MODULE__, :mode}, :ok) do
      :expired ->
        {:ok,
         %{
           status_code: 403,
           body: error("ExpiredToken", "The security token included in the request is expired")
         }}

      {:throttle_once, ref} ->
        if :persistent_term.get({__MODULE__, ref}, false) do
          {:ok, %{status_code: 200, body: answer(params)}}
        else
          :persistent_term.put({__MODULE__, ref}, true)
          {:ok, %{status_code: 400, body: error("Throttling", "Rate exceeded")}}
        end

      :stack_gone ->
        if params["Action"] == "ListStacks",
          do: {:ok, %{status_code: 200, body: answer(params)}},
          else: {:ok, %{status_code: 400, body: error("ValidationError", "Stack does not exist")}}

      :ok ->
        {:ok, %{status_code: 200, body: answer(params)}}
    end
  end

  defp error(code, msg),
    do:
      ~s(<ErrorResponse #{@ns}><Error><Type>Sender</Type><Code>#{code}</Code><Message>#{msg}</Message></Error></ErrorResponse>)

  defp answer(%{"Action" => "ListStacks"}) do
    wrap("ListStacks", """
    <StackSummaries>
      <member><StackName>web-prod</StackName><StackStatus>UPDATE_COMPLETE</StackStatus><LastUpdatedTime>2026-11-02T10:05:00Z</LastUpdatedTime></member>
      <member><StackName>web-gone</StackName><StackStatus>DELETE_COMPLETE</StackStatus></member>
    </StackSummaries>
    """)
  end

  defp answer(%{"Action" => "DescribeStacks"}) do
    wrap("DescribeStacks", """
    <Stacks><member>
      <StackName>web-prod</StackName><StackStatus>UPDATE_COMPLETE</StackStatus>
      <CreationTime>2026-11-01T09:00:00Z</CreationTime><LastUpdatedTime>2026-11-02T10:05:00Z</LastUpdatedTime>
      <Outputs><member><OutputKey>FnArn</OutputKey><OutputValue>arn:aws:lambda:fn</OutputValue></member></Outputs>
    </member></Stacks>
    """)
  end

  defp answer(%{"Action" => "ListStackResources"}) do
    wrap("ListStackResources", """
    <StackResourceSummaries>
      <member><LogicalResourceId>Role</LogicalResourceId><PhysicalResourceId>role-1</PhysicalResourceId><ResourceType>AWS::IAM::Role</ResourceType><ResourceStatus>CREATE_COMPLETE</ResourceStatus><LastUpdatedTimestamp>2026-11-01T09:00:40Z</LastUpdatedTimestamp></member>
      <member><LogicalResourceId>Fn</LogicalResourceId><PhysicalResourceId>fn-1</PhysicalResourceId><ResourceType>AWS::Lambda::Function</ResourceType><ResourceStatus>CREATE_COMPLETE</ResourceStatus><LastUpdatedTimestamp>2026-11-01T09:01:30Z</LastUpdatedTimestamp></member>
    </StackResourceSummaries>
    """)
  end

  defp answer(%{"Action" => "GetTemplate"}) do
    body = File.read!("test/fixtures/cloudformation/template.json")
    wrap("GetTemplate", "<TemplateBody>#{Plug.HTML.html_escape(body)}</TemplateBody>")
  end

  defp answer(%{"Action" => "DescribeStackEvents"}) do
    members =
      Jason.decode!(File.read!("test/fixtures/cloudformation/events.json"))
      |> Enum.map_join(fn e ->
        "<member>" <> Enum.map_join(e, fn {k, v} -> "<#{k}>#{v}</#{k}>" end) <> "</member>"
      end)

    wrap("DescribeStackEvents", "<StackEvents>#{members}</StackEvents>")
  end

  defp wrap(action, inner),
    do:
      ~s(<#{action}Response #{@ns}><#{action}Result>#{inner}</#{action}Result></#{action}Response>)
end
