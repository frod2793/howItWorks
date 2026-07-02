using System.Collections.Generic;
using Domain.InGame;
using Features.InGame;
using NUnit.Framework;

namespace Game.Tests.EditMode
{
    /// <summary>
    /// [기능]: 인게임 ViewModel의 순수 상태 변경 및 이벤트 발행 흐름을 검증합니다.
    /// [작성자]: 윤승종
    /// </summary>
    public class InGameViewModelEditModeTests
    {
        #region 테스트 메서드

        /// <summary>
        /// [기능]: 대사 표시 시 현재 대사와 선택지 상태가 갱신되는지 검증합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-03
        /// [마지막 수정 작성자]: 윤승종
        /// [수정 내용]: EditMode 테스트 러너 검증을 위한 대사 ViewModel 테스트를 추가했습니다.
        /// </summary>
        [Test]
        public void DialogueViewModel_DisplayDialogue_UpdatesCurrentDialogueAndClearsChoices()
        {
            DialogueViewModel viewModel = new DialogueViewModel();
            DialogueDTO expectedDialogue = new DialogueDTO();
            expectedDialogue.SpeakerName = "테스터";
            expectedDialogue.Content = "대사 진행 상태 검증";
            expectedDialogue.CurrentLine = 12;
            expectedDialogue.TotalLines = 48;

            DialogueDTO receivedDialogue = null;
            List<DialogueChoiceDTO> receivedChoices = new List<DialogueChoiceDTO>();
            viewModel.OnDialogueUpdated += dialogue => receivedDialogue = dialogue;
            viewModel.OnChoicesUpdated += choices => receivedChoices = choices;

            viewModel.DisplayChoices(new List<DialogueChoiceDTO>());
            viewModel.DisplayDialogue(expectedDialogue);

            Assert.AreSame(expectedDialogue, viewModel.CurrentDialogue);
            Assert.AreSame(expectedDialogue, receivedDialogue);
            Assert.IsFalse(viewModel.IsDisplayingChoices);
            Assert.IsNull(receivedChoices);
        }

        /// <summary>
        /// [기능]: 선택지 선택 시 선택지 상태 해제와 선택 이벤트가 발행되는지 검증합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-03
        /// [마지막 수정 작성자]: 윤승종
        /// [수정 내용]: 선택지 이벤트 흐름 검증 테스트를 추가했습니다.
        /// </summary>
        [Test]
        public void DialogueViewModel_SelectChoice_PublishesSelectedChoiceAndClearsChoiceList()
        {
            DialogueViewModel viewModel = new DialogueViewModel();
            int selectedChoiceId = -1;
            bool isChoiceListCleared = false;

            viewModel.OnChoiceSelected += choiceId => selectedChoiceId = choiceId;
            viewModel.OnChoicesUpdated += choices => isChoiceListCleared = choices == null;

            viewModel.DisplayChoices(new List<DialogueChoiceDTO>
            {
                new DialogueChoiceDTO
                {
                    ChoiceId = 101,
                    Title = "선택지"
                }
            });
            viewModel.SelectChoice(101);

            Assert.AreEqual(101, selectedChoiceId);
            Assert.IsFalse(viewModel.IsDisplayingChoices);
            Assert.IsTrue(isChoiceListCleared);
        }

        /// <summary>
        /// [기능]: 자동 진행 상태 변경 시 중복 없이 상태 변경 이벤트가 발행되는지 검증합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-03
        /// [마지막 수정 작성자]: 윤승종
        /// [수정 내용]: 자동 진행 상태 이벤트 테스트를 추가했습니다.
        /// </summary>
        [Test]
        public void DialogueViewModel_IsAutoPlayActive_PublishesOnlyWhenValueChanged()
        {
            DialogueViewModel viewModel = new DialogueViewModel();
            int eventCount = 0;
            bool receivedState = false;

            viewModel.OnAutoPlayStatusChanged += isActive =>
            {
                eventCount++;
                receivedState = isActive;
            };

            viewModel.IsAutoPlayActive = true;
            viewModel.IsAutoPlayActive = true;

            Assert.AreEqual(1, eventCount);
            Assert.IsTrue(receivedState);
        }

        /// <summary>
        /// [기능]: 사이드 패널 ViewModel이 DTO를 변경 없이 발행하는지 검증합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-03
        /// [마지막 수정 작성자]: 윤승종
        /// [수정 내용]: 사이드 패널 데이터 이벤트 테스트를 추가했습니다.
        /// </summary>
        [Test]
        public void SidePanelViewModel_UpdateSidePanelData_PublishesSameDto()
        {
            SidePanelViewModel viewModel = new SidePanelViewModel();
            SidePanelDTO expectedData = new SidePanelDTO();
            expectedData.CatoStocks = 3;
            expectedData.MaxCatoStocks = 5;
            expectedData.PassedScenesInfo = "구역 ㆍ 제3 보존구";
            expectedData.IsLongingActive = true;

            SidePanelDTO receivedData = null;
            viewModel.OnSidePanelDataChanged += data => receivedData = data;

            viewModel.UpdateSidePanelData(expectedData);

            Assert.AreSame(expectedData, receivedData);
            Assert.AreEqual("구역 ㆍ 제3 보존구", receivedData.PassedScenesInfo);
            Assert.IsTrue(receivedData.IsLongingActive);
        }

        /// <summary>
        /// [기능]: 씬 정보 ViewModel이 표시 문자열과 설정 요청 이벤트를 갱신하는지 검증합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-03
        /// [마지막 수정 작성자]: 윤승종
        /// [수정 내용]: 씬 정보 ViewModel 표시 데이터 테스트를 추가했습니다.
        /// </summary>
        [Test]
        public void SceneInfoViewModel_UpdateSceneInfo_FormatsDisplayTextAndPublishesEvents()
        {
            FakeSoundService soundService = new FakeSoundService();
            SceneInfoViewModel viewModel = new SceneInfoViewModel(soundService);
            SceneInfoDTO sceneInfo = new SceneInfoDTO();
            sceneInfo.ActName = "D1";
            sceneInfo.SceneNumber = 3;
            sceneInfo.SceneTitle = "보존구";
            sceneInfo.Location = "제3 보존구";
            sceneInfo.TimeOfDay = "심야";
            sceneInfo.Playthrough = 2;

            bool isSceneInfoChanged = false;
            bool isSceneInfoUpdated = false;
            bool isSettingsRequested = false;
            viewModel.OnSceneInfoChanged += info => isSceneInfoChanged = info == sceneInfo;
            viewModel.OnSceneInfoUpdated += () => isSceneInfoUpdated = true;
            viewModel.OnRequestSettings += () => isSettingsRequested = true;

            viewModel.UpdateSceneInfo(sceneInfo);
            viewModel.RequestSettings();
            viewModel.PlayClickSound();

            Assert.AreEqual("D1 · 씬 3 — 보존구", viewModel.DisplaySceneTitle);
            Assert.AreEqual("제3 보존구 · 심야", viewModel.DisplayLocation);
            Assert.AreEqual("2회차", viewModel.DisplayPlaythrough);
            Assert.IsTrue(isSceneInfoChanged);
            Assert.IsTrue(isSceneInfoUpdated);
            Assert.IsTrue(isSettingsRequested);
            Assert.AreEqual(1, soundService.SfxPlayCount);
        }

        #endregion

        #region 테스트 대역

        /// <summary>
        /// [기능]: 사운드 재생 요청 여부만 기록하는 테스트 대역입니다.
        /// [작성자]: 윤승종
        /// </summary>
        private sealed class FakeSoundService : ISoundService
        {
            public int SfxPlayCount { get; private set; }
            public float MasterVolume { get; private set; }
            public float BGMVolume { get; private set; }
            public float SFXVolume { get; private set; }
            public float VoiceVolume { get; private set; }
            public bool MuteOnFocusLost { get; private set; }

            /// <summary>
            /// [기능]: 테스트 환경에서 배경 음악 재생 요청을 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void PlayBGM(string key, float fadeDuration = 0.5f, bool loop = true)
            {
            }

            /// <summary>
            /// [기능]: 테스트 환경에서 배경 음악 정지 요청을 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void StopBGM(float fadeDuration = 0.5f)
            {
            }

            /// <summary>
            /// [기능]: 효과음 재생 요청 횟수를 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void PlaySFX(string key, float volumeScale = 1.0f)
            {
                SfxPlayCount++;
            }

            /// <summary>
            /// [기능]: 테스트 환경에서 루프 효과음 재생 요청을 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void PlayLoopSFX(string key, float volumeScale = 1.0f)
            {
            }

            /// <summary>
            /// [기능]: 테스트 환경에서 루프 효과음 정지 요청을 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void StopLoopSFX()
            {
            }

            /// <summary>
            /// [기능]: 테스트용 BGM/SFX 볼륨 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetVolume(float bgmVolume, float sfxVolume)
            {
                BGMVolume = bgmVolume;
                SFXVolume = sfxVolume;
            }

            /// <summary>
            /// [기능]: 테스트용 마스터 볼륨 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetMasterVolume(float volume)
            {
                MasterVolume = volume;
            }

            /// <summary>
            /// [기능]: 테스트용 BGM 볼륨 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetBGMVolume(float volume)
            {
                BGMVolume = volume;
            }

            /// <summary>
            /// [기능]: 테스트용 SFX 볼륨 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetSFXVolume(float volume)
            {
                SFXVolume = volume;
            }

            /// <summary>
            /// [기능]: 테스트용 보이스 볼륨 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetVoiceVolume(float volume)
            {
                VoiceVolume = volume;
            }

            /// <summary>
            /// [기능]: 테스트용 포커스 상실 음소거 값을 기록합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SetMuteOnFocusLost(bool mute)
            {
                MuteOnFocusLost = mute;
            }

            /// <summary>
            /// [기능]: 테스트 환경에서 저장된 설정 로드를 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void LoadSettings()
            {
            }

            /// <summary>
            /// [기능]: 테스트 환경에서 설정 저장을 무시합니다.
            /// [작성자]: 윤승종
            /// [수정 날짜]: 2026-07-03
            /// [마지막 수정 작성자]: 윤승종
            /// [수정 내용]: 테스트 대역 구현을 추가했습니다.
            /// </summary>
            public void SaveSettings()
            {
            }
        }

        #endregion
    }
}
