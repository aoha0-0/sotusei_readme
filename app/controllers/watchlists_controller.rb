# frozen_string_literal: true

class WatchlistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_watchlist, only: %i[show edit update toggle_completion]

  def index
    watchlists = current_user.watchlists

    watchlists = watchlists.tagged_with(params[:tag]) if params[:tag].present?
    watchlists = watchlists.title_containing(params[:title]) if params[:title].present?

    # 1. 「これからの予定」
    @future_watchlists = watchlists.upcoming

    # 2. 「これまでの足跡」
    @past_watchlists = watchlists.past
  end

  def show; end

  def new
    @watchlist = current_user.watchlists.build
  end

  def create
    @watchlist = current_user.watchlists.build(watchlist_params)

    if @watchlist.save
      @watchlist.save_tags
      current_user.update!(onboarding_completed_at: Time.current) if current_user.onboarding_completed_at.nil?

      redirect_to watchlists_path, notice: '新しい予定を登録しました'
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @watchlist.tag_names = @watchlist.tags.pluck(:name).join(', ')
  end

  def update
    if @watchlist.update(watchlist_params)
      @watchlist.save_tags
      redirect_to watchlist_path(@watchlist), notice: '更新しました'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def toggle_completion
    @watchlist.update!(is_done: !@watchlist.is_done?)

    notice = @watchlist.is_done? ? '予定を完了にしました' : '予定を未完了に戻しました'
    redirect_to watchlist_path(@watchlist), notice: notice
  end

  def destroy
    watchlist = current_user.watchlists.find(params[:id])
    watchlist.destroy!
    redirect_to watchlists_path, notice: 'これからの予定から削除しました', status: :see_other
  end

  def test_mail
    # 即席でメールを送信するコマンド
    ActionMailer::Base.mail(
      from: 'info@fanpocket.fun',
      to: 'aquarium.swing@gmail.com',
      subject: '本番環境からの疎通テスト',
      body: 'Resendと独自ドメインの紐付けテストです。これが届いていれば成功です！'
    ).deliver_now

    render plain: 'テストメールを送信しました！Gmailを確認してください。'
  end

  private

  def set_watchlist
    @watchlist = current_user.watchlists.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 他人のIDを指定して探せなかった場合、一覧へ戻す
    redirect_to watchlists_path, alert: '指定されたページは見つかりません'
  end

  WATCHLIST_PARAMS = %i[
    title
    memo
    url
    start_at
    end_at
    reception_type
    reception_detail
    tag_names
  ].freeze

  def watchlist_params
    params.require(:watchlist).permit(*WATCHLIST_PARAMS)
  end
end
