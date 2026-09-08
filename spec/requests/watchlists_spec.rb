# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Watchlists', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe 'POST /watchlists' do
    context '有効なパラメータの場合' do
      let(:valid_params) do
        {
          watchlist: {
            title: 'チケット申し込み',
            start_at: 1.day.from_now,
            end_at: 3.days.from_now,
            reception_type: :lottery,
            reception_detail: 'FC先行'
          }
        }
      end

      it '予定を1件作成する' do
        expect do
          post watchlists_path, params: valid_params
        end.to change(Watchlist, :count).by(1)
      end

      it '予定一覧へリダイレクトする' do
        post watchlists_path, params: valid_params

        expect(response).to redirect_to(watchlists_path)
      end
    end

    context '無効なパラメータの場合' do
      let(:invalid_params) do
        {
          watchlist: {
            title: '',
            start_at: 1.day.from_now,
            end_at: 3.days.from_now
          }
        }
      end

      it '予定を作成しない' do
        expect do
          post watchlists_path, params: invalid_params
        end.not_to change(Watchlist, :count)
      end

      it '422を返す' do
        post watchlists_path, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'タグを含む有効なパラメータの場合' do
      let(:valid_params_with_tags) do
        {
          watchlist: {
            title: 'チケット申し込み',
            start_at: 1.day.from_now,
            end_at: 3.days.from_now,
            tag_names: 'ライブ, チケット'
          }
        }
      end

      it 'タグを保存して予定に紐付ける' do
        post watchlists_path, params: valid_params_with_tags

        watchlist = Watchlist.last

        expect(watchlist.tags.pluck(:name)).to contain_exactly(
          'ライブ',
          'チケット'
        )
      end
    end
  end

  describe 'PATCH /watchlists/:id/toggle_completion' do
    context '未完了の予定の場合' do
      let(:watchlist) do
        create(
          :watchlist,
          user: user,
          is_done: false
        )
      end

      it '予定を完了にする' do
        expect do
          patch toggle_completion_watchlist_path(watchlist)
        end.to change { watchlist.reload.is_done }.from(false).to(true)
      end

      it '予定詳細へリダイレクトする' do
        patch toggle_completion_watchlist_path(watchlist)

        expect(response).to redirect_to(watchlist_path(watchlist))
      end

      it '完了したことを通知する' do
        patch toggle_completion_watchlist_path(watchlist)

        expect(flash[:notice]).to eq('予定を完了にしました')
      end
    end

    context '完了した予定の場合' do
      let(:watchlist) do
        create(
          :watchlist,
          user: user,
          is_done: true
        )
      end

      it '予定を未完了に戻す' do
        expect do
          patch toggle_completion_watchlist_path(watchlist)
        end.to change { watchlist.reload.is_done }.from(true).to(false)
      end

      it '未完了に戻したことを通知する' do
        patch toggle_completion_watchlist_path(watchlist)

        expect(flash[:notice]).to eq('予定を未完了に戻しました')
      end
    end

    context '他のユーザーの予定の場合' do
      let(:other_user) { create(:user) }

      let(:other_watchlist) do
        create(
          :watchlist,
          user: other_user,
          is_done: false
        )
      end

      it '完了状態を変更しない' do
        expect do
          patch toggle_completion_watchlist_path(other_watchlist)
        end.not_to(change { other_watchlist.reload.is_done })
      end

      it '予定一覧へリダイレクトする' do
        patch toggle_completion_watchlist_path(other_watchlist)

        expect(response).to redirect_to(watchlists_path)
      end
    end

    context 'ログインしていない場合' do
      let(:watchlist) do
        create(
          :watchlist,
          user: user,
          is_done: false
        )
      end

      it 'ログイン画面へリダイレクトする' do
        sign_out user

        patch toggle_completion_watchlist_path(watchlist)

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE /watchlists/:id' do
    let!(:watchlist) do
      create(
        :watchlist,
        user: user
      )
    end

    it '予定を1件削除する' do
      expect do
        delete watchlist_path(watchlist)
      end.to change(Watchlist, :count).by(-1)
    end

    it '予定一覧へリダイレクトする' do
      delete watchlist_path(watchlist)

      expect(response).to redirect_to(watchlists_path)
    end

    context '他のユーザーの予定を削除しようとした場合' do
      let(:other_user) { create(:user) }

      let!(:other_watchlist) do
        create(
          :watchlist,
          user: other_user
        )
      end

      it '他のユーザーの予定を削除しない' do
        expect do
          delete watchlist_path(other_watchlist)
        end.not_to change(Watchlist, :count)

        expect(Watchlist.exists?(other_watchlist.id)).to be true
      end

      it '404を返す' do
        delete watchlist_path(other_watchlist)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe '認証' do
    context 'ログインしていない場合' do
      it '予定一覧へアクセスするとログイン画面へリダイレクトする' do
        sign_out user

        get watchlists_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /watchlists' do
    context 'ログインしている場合' do
      it '自分の予定だけを表示する' do
        own_watchlist = create(
          :watchlist,
          user: user,
          title: 'チケット申し込み'
        )

        other_user = create(:user)

        other_watchlist = create(
          :watchlist,
          user: other_user,
          title: 'グッズ販売'
        )

        get watchlists_path

        expect(response.body).to include(own_watchlist.title)
        expect(response.body).not_to include(other_watchlist.title)
      end
    end

    context 'タグを指定した場合' do
      it '指定したタグの予定だけを表示する' do
        live_watchlist = create(
          :watchlist,
          user: user,
          title: 'ライブ予定'
        )

        goods_watchlist = create(
          :watchlist,
          user: user,
          title: 'グッズ販売'
        )

        live_watchlist.tag_names = 'ライブ'
        live_watchlist.save_tags

        goods_watchlist.tag_names = 'グッズ'
        goods_watchlist.save_tags

        get watchlists_path, params: { tag: 'ライブ' }

        expect(response.body).to include(live_watchlist.title)
        expect(response.body).not_to include(goods_watchlist.title)
      end
    end

    context 'タイトルを指定した場合' do
      it 'タイトルが部分一致する予定だけを表示する' do
        matched_watchlist = create(
          :watchlist,
          user: user,
          title: '東京ドーム公演'
        )

        unmatched_watchlist = create(
          :watchlist,
          user: user,
          title: 'グッズ販売'
        )

        get watchlists_path, params: { title: '東京ドーム' }

        expect(response.body).to include(matched_watchlist.title)
        expect(response.body).not_to include(unmatched_watchlist.title)
      end

      it '他のユーザーの予定は表示しない' do
        own_watchlist = create(
          :watchlist,
          user: user,
          title: '東京ドーム公演'
        )

        other_user = create(:user)

        other_watchlist = create(
          :watchlist,
          user: other_user,
          title: '東京ドーム追加公演'
        )

        get watchlists_path, params: { title: '東京ドーム' }

        expect(response.body).to include(own_watchlist.title)
        expect(response.body).not_to include(other_watchlist.title)
      end
    end

    context 'タイトルとタグを指定した場合' do
      it '両方の条件に一致する予定だけを表示する' do
        matched_watchlist = create(
          :watchlist,
          user: user,
          title: '東京ドーム公演'
        )

        title_only_watchlist = create(
          :watchlist,
          user: user,
          title: '東京ドームグッズ販売'
        )

        tag_only_watchlist = create(
          :watchlist,
          user: user,
          title: '大阪公演'
        )

        matched_watchlist.tag_names = 'ライブ'
        matched_watchlist.save_tags

        title_only_watchlist.tag_names = 'グッズ'
        title_only_watchlist.save_tags

        tag_only_watchlist.tag_names = 'ライブ'
        tag_only_watchlist.save_tags

        get watchlists_path, params: {
          title: '東京ドーム',
          tag: 'ライブ'
        }

        expect(response.body).to include(matched_watchlist.title)
        expect(response.body).not_to include(title_only_watchlist.title)
        expect(response.body).not_to include(tag_only_watchlist.title)
      end
    end
  end

  describe 'GET /watchlists/:id' do
    context '自分の予定の場合' do
      it '予定詳細を表示する' do
        watchlist = create(
          :watchlist,
          user: user,
          title: 'チケット申し込み'
        )

        get watchlist_path(watchlist)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('チケット申し込み')
      end
    end

    context '他のユーザーの予定の場合' do
      it '予定一覧へリダイレクトする' do
        other_user = create(:user)
        other_watchlist = create(
          :watchlist,
          user: other_user
        )

        get watchlist_path(other_watchlist)

        expect(response).to redirect_to(watchlists_path)
      end
    end
  end

  describe 'GET /watchlists/:id/edit' do
    context '自分の予定の場合' do
      it '編集画面を表示する' do
        watchlist = create(
          :watchlist,
          user: user
        )

        get edit_watchlist_path(watchlist)

        expect(response).to have_http_status(:ok)
      end
    end

    context '他のユーザーの予定の場合' do
      it '予定一覧へリダイレクトする' do
        other_user = create(:user)
        other_watchlist = create(
          :watchlist,
          user: other_user
        )

        get edit_watchlist_path(other_watchlist)

        expect(response).to redirect_to(watchlists_path)
      end
    end
  end
end
