defmodule Commanded.Middleware.AuditingTest do
  use ExUnit.Case

  alias Commanded.Middleware.Auditing
  alias Commanded.Middleware.Auditing.{CommandAudit,Repo}
  alias Commanded.Middleware.Pipeline

  defmodule Command do
    defstruct [:name, :age, :password, :password_confirmation, :secret]
  end

  describe "before command dispatch" do
    setup [
      :execute_before_dispatch,
      :get_audit,
    ]

    test "should record command", %{pipeline: pipeline, audit: audit} do
      assert audit != nil
      assert is_nil audit.success
      assert audit.occurred_at != nil
      assert audit.occurred_at == pipeline.assigns.occurred_at
      assert audit.causation_id == pipeline.causation_id
      assert audit.correlation_id == pipeline.correlation_id
      assert audit.command_uuid == pipeline.command_uuid
      assert audit.data == "{\"secret\":\"[FILTERED]\",\"password_confirmation\":\"[FILTERED]\",\"password\":\"[FILTERED]\",\"name\":\"Ben\",\"age\":34}"
      assert audit.metadata == "{\"user\":\"user@example.com\"}"
      assert is_nil audit.execution_duration_usecs
    end
  end

  describe "after successful command dispatch" do
    setup [
      :execute_before_dispatch,
      :execute_after_dispatch,
      :get_audit,
    ]

    test "should record success", %{audit: audit} do
      assert audit.success == true
      assert is_nil audit.error
      assert is_nil audit.error_reason
      assert audit.execution_duration_usecs > 0
    end
  end

  describe "after failed command dispatch" do
    setup [
      :execute_before_dispatch,
      :execute_after_failure,
      :get_audit,
    ]

    test "should record failure", %{audit: audit} do
      assert audit.success == false
      assert audit.error == ":failed"
      assert audit.error_reason == "\"failure\""
      assert audit.execution_duration_usecs > 0
    end
  end

  describe "after failed command dispatch but no reason" do
    setup [
      :execute_before_dispatch,
      :execute_after_failure_no_reason,
      :get_audit,
    ]

    test "should record failure", %{audit: audit} do
      assert audit.success == false
      assert audit.error == ":failed"
      assert is_nil audit.error_reason
      assert audit.execution_duration_usecs > 0
    end
  end

  defp execute_before_dispatch(_context) do
    pipeline = Auditing.before_dispatch(%Pipeline{
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      command: %Command{name: "Ben", age: 34, password: 1234, password_confirmation: 1234, secret: "I'm superdupersecret!"},
      command_uuid: UUID.uuid4(),
      metadata: %{user: "user@example.com"},
    })

    [pipeline: pipeline]
  end

  defp execute_after_dispatch(%{pipeline: pipeline}) do
    pipeline = Auditing.after_dispatch(pipeline)

    [pipeline: pipeline]
  end

  defp execute_after_failure(%{pipeline: pipeline}) do
    pipeline =
      pipeline
      |> Pipeline.assign(:error, :failed)
      |> Pipeline.assign(:error_reason, "failure")
      |> Auditing.after_failure()

    [pipeline: pipeline]
  end

  defp execute_after_failure_no_reason(%{pipeline: pipeline}) do
    pipeline =
      pipeline
      |> Pipeline.assign(:error, :failed)
      |> Auditing.after_failure

    [pipeline: pipeline]
  end

  defp get_audit(%{pipeline: %Pipeline{command_uuid: command_uuid}}) do
    audit = Repo.get(CommandAudit, command_uuid)

    [audit: audit]
  end
end
