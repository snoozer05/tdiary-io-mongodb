require 'spec_helper'

describe TDiary::IO::MongoDB do
	it 'is based on TDiary::IO::Base' do
		expect(TDiary::IO::MongoDB < TDiary::IO::Base).to be true
	end

	describe "#save_cgi_conf and #load_cgi_conf" do
		let(:conf) { DummyConf.new }

		it { expect(TDiary::IO::MongoDB.load_cgi_conf(conf)).to be_empty }

		context "given body" do
			before do
				TDiary::IO::MongoDB.save_cgi_conf(conf, 'foo')
			end

			it { expect(TDiary::IO::MongoDB.load_cgi_conf(conf)).to eq 'foo' }

			context "update" do
				before do
					TDiary::IO::MongoDB.save_cgi_conf(conf, 'bar')
				end
				it { expect(TDiary::IO::MongoDB.load_cgi_conf(conf)).to eq 'bar' }
			end
		end
	end

	describe "plugin storage support" do
		it ".plugin_open returns nil" do
			expect(TDiary::IO::MongoDB.plugin_open(nil)).to be nil
		end

		it ".plugin_close do nothing" do
			# nothing
		end

		describe ".plugin_transaction" do
			let(:storage){ TDiary::IO::MongoDB.plugin_open(nil) }

			it "store/restore data" do
				TDiary::IO::MongoDB.plugin_transaction(storage, 'test_plugin') do |db|
					db.set('test_key', 'test_value')
					expect(db.get('test_key')).to eq('test_value')
				end
			end

			it "update data" do
				TDiary::IO::MongoDB.plugin_transaction(storage, 'test_plugin') do |db|
					db.set('test_key', 'test_update')
					expect(db.get('test_key')).to eq('test_update')
				end
			end

			it "delete data" do
				TDiary::IO::MongoDB.plugin_transaction(storage, 'test_plugin') do |db|
					db.set('test_key', 'test_delete')
					db.delete('test_key')
					expect(db.get('test_key')).to eq(nil)
				end
			end

			it "keys" do
				TDiary::IO::MongoDB.plugin_transaction(storage, 'test_plugin') do |db|
					db.set('test_key1', 'test_value1')
					db.set('test_key2', 'test_value2')
					expect(db.keys).to match_array ['test_key1', 'test_key2']
				end
			end
		end
	end

	describe "#transaction" do
		let(:io) { TDiary::IO::MongoDB.new(DummyTDiary.new) }
		let(:today) { Time.now.strftime( '%Y%m%d' ) }
		let(:diary) { DummyStyle.new('', "foo", "bar", '') }

		before do
			io.transaction( Time.now ) do |diaries|
				@diaries = diaries
				@diaries[today] = diary
				TDiary::TDiaryBase::DIRTY_DIARY
			end
		end

		subject { TDiary::IO::MongoDB::Diary.where(diary_id: today).first }

		it "insert diary" do
			expect(subject).to_not be_nil
			expect(subject[:title]).to eq "foo"
			expect(subject[:body]).to eq "bar"
		end

		it "restore diary" do
			io.transaction( Time.now ) do |diaries|
				@diaries = diaries
				expect(@diaries[today].title).to eq "foo"
				expect(@diaries[today].to_src).to eq "bar"
				TDiary::TDiaryBase::DIRTY_NONE
			end
		end

		context "update diary" do
			let(:diary2) { DummyStyle.new('' , "bar", "foo", '') }

			before do
				io.transaction( Time.now ) do |diaries|
					@diaries = diaries
					@diaries[today] = diary2
					TDiary::TDiaryBase::DIRTY_DIARY
				end
			end

			subject { TDiary::IO::MongoDB::Diary.where(diary_id: today) }

			it "update contents of diary" do
				expect(subject).to_not be_nil
				expect(subject.count).to eq 1
				expect(subject.first[:title]).to eq "bar"
				expect(subject.first[:body]).to eq "foo"
			end
		end

		context "add comment" do
			let(:comment) { TDiary::Comment.new('hoge', 'hoge@example.com', 'foobarbaz') }

			before do
				io.transaction( Time.now ) do |diaries|
					@diaries = diaries
					diary.add_comment(comment)
					@diaries[today] = diary
					TDiary::TDiaryBase::DIRTY_COMMENT
				end
			end

			subject { TDiary::IO::MongoDB::Diary.where(diary_id: today).first }

			it "append a comment to a diary" do
				expect(subject.comments.size).to eq 1
				expect(subject.comments.first.name).to eq 'hoge'
				expect(subject.comments.first.mail).to eq 'hoge@example.com'
				expect(subject.comments.first.body).to eq 'foobarbaz'
			end

			it "restore comment" do
				io.transaction( Time.now ) do |diaries|
					diaries.each do |date, diary|
						diary.each_comment(1) do |com|
							expect(com.name).to eq "hoge"
							expect(com.mail).to eq "hoge@example.com"
							expect(com.body).to eq "foobarbaz"
						end
					end
					TDiary::TDiaryBase::DIRTY_NONE
				end
			end
		end
	end
end
