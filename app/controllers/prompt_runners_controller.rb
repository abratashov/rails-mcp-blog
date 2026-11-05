# frozen_string_literal: true

class PromptRunnersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_prompt_runner

  def index
    @prompts = AI::PromptRunnerSession.available_prompts
  end

  def show
    assign_result(@prompt_runner.show)
    head :not_found if @result.not_found
  end

  def create
    assign_result(@prompt_runner.submit(params[:message], arguments: prompt_arguments))
    return head :not_found if @result.not_found
    return redirect_to prompt_runner_path(params[:prompt_name]), status: :see_other if @result.success

    render :show, status: :unprocessable_content
  end

  def destroy
    @prompt_runner.end_session
    redirect_to prompt_runner_path(params[:prompt_name]), status: :see_other, notice: "Session ended."
  end

  private

  def set_prompt_runner
    @prompt_runner = AI::PromptRunnerSession.new(
      user: current_user,
      session: session,
      prompt_name: params[:prompt_name]
    )
  end

  def prompt_arguments
    arguments = params[:arguments]
    arguments.respond_to?(:to_unsafe_h) ? arguments.to_unsafe_h : {}
  end

  def assign_result(result)
    @result = result
    @messages = result.messages
    @started = result.started
    @error = result.error
    @message = result.message
    @prompt = result.prompt
    @arguments = result.arguments
  end
end
