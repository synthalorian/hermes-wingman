# frozen_string_literal: true

class WebhooksController < ApplicationController
  before_action :set_webhook, only: [:show, :edit, :update, :destroy]

  def index
    @webhooks = Webhook.order(created_at: :desc)
  end

  def show
  end

  def new
    @webhook = Webhook.new
  end

  def create
    @webhook = Webhook.new(webhook_params)
    @webhook.active = true
    if @webhook.save
      redirect_to @webhook, notice: "Webhook created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @webhook.update(webhook_params)
      redirect_to @webhook, notice: "Webhook updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @webhook.destroy
    redirect_to webhooks_path, notice: "Webhook deleted."
  end

  private

  def set_webhook
    @webhook = Webhook.find(params[:id])
  end

  def webhook_params
    params.require(:webhook).permit(:name, :url, :events, :secret, :active)
  end
end
