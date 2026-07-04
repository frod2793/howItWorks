using System;
using System.Collections.Generic;
using Domain.InGame;

/// <summary>
/// [기능]: 도감 도메인의 필터링, 진척도 연산 및 비즈니스 로직을 가공해 제공하는 뷰모델 클래스입니다.
/// [작성자]: 윤승종
/// </summary>
namespace Features.InGame
{
    public class InGameEncyclopediaViewModel : IInGameEncyclopediaViewModel
    {
        #region 이벤트 (Events)
        public event Action OnDataChanged;
        public event Action<EncyclopediaItemDTO> OnDetailOpened;
        public event Action OnDetailClosed;
        #endregion

        #region 내부 필드 (Private Fields)
        private string m_currentCategory = "Character";
        private bool m_showOnlyUnlocked = false;
        private List<string> m_unlockedItems = new List<string>();
        private List<EncyclopediaItemDTO> m_allItems = new List<EncyclopediaItemDTO>();
        private EncyclopediaItemDTO m_activeDetailItem;
        #endregion

        #region 프로퍼티 (Properties)
        public string CurrentCategory => m_currentCategory;
        public bool ShowOnlyUnlocked => m_showOnlyUnlocked;
        public EncyclopediaItemDTO ActiveDetailItem => m_activeDetailItem;

        public IReadOnlyList<EncyclopediaItemDTO> CurrentItems
        {
            get
            {
                var list = new List<EncyclopediaItemDTO>();
                for (int i = 0; i < m_allItems.Count; i++)
                {
                    var item = m_allItems[i];
                    if (item.Category == m_currentCategory)
                    {
                        if (m_showOnlyUnlocked && !item.IsUnlocked)
                        {
                            continue;
                        }
                        list.Add(item);
                    }
                }
                return list;
            }
        }
        #endregion

        #region 초기화 (Initialization)
        public void Initialize(List<string> unlockedItems)
        {
            // 기획 시연 및 목업 확인을 위해 임시 강제 해금 목록 세팅
            m_unlockedItems = new List<string>
            {
                "char_elena", "char_rain", "char_system_ai",
                "item_cato", "item_keycard", "item_record_tape",
                "cg_start_loop", "cg_collapsed", "cg_elena_smile",
                "bgm_theme", "bgm_plaza", "bgm_conflict"
            };

            LoadMockDatabase();
            OnDataChanged?.Invoke();
        }
        #endregion

        #region 공개 메서드 (Public Methods)
        public void func_SelectCategory(string category)
        {
            if (m_currentCategory == category)
            {
                return;
            }
            m_currentCategory = category;
            func_CloseDetail();
            OnDataChanged?.Invoke();
        }

        public void func_ToggleFilter()
        {
            m_showOnlyUnlocked = !m_showOnlyUnlocked;
            OnDataChanged?.Invoke();
        }

        public void func_SelectCard(string itemId)
        {
            var item = m_allItems.Find(x => x.Id == itemId);
            if (item != null)
            {
                m_activeDetailItem = item;
                OnDetailOpened?.Invoke(item);
            }
        }

        public void func_CloseDetail()
        {
            m_activeDetailItem = null;
            OnDetailClosed?.Invoke();
        }

        public (int unlocked, int total) GetCategoryProgress(string category)
        {
            int total = 0;
            int unlocked = 0;
            for (int i = 0; i < m_allItems.Count; i++)
            {
                if (m_allItems[i].Category == category)
                {
                    total++;
                    if (m_allItems[i].IsUnlocked)
                    {
                        unlocked++;
                    }
                }
            }
            return (unlocked, total);
        }
        #endregion

        #region 내부 메서드 (Private Methods)
        private void LoadMockDatabase()
        {
            m_allItems.Clear();

            // 1. 캐릭터 카테고리 (해금 3, 미해금 3)
            AddMockItem("char_elena", "엘레나", "이 루프를 반복하는 주요 관찰 대상이자 동반자.", "관찰 대상", "Character", "Icons/Elena");
            AddMockItem("char_rain", "레인", "독자적으로 움직이는 연방정부 수사관.", "수사관", "Character", "Icons/Rain");
            AddMockItem("char_system_ai", "마더 AI", "루프 실험실 시스템을 감시하고 제어하는 인공지능.", "관리자 AI", "Character", "Icons/SystemAI");
            AddMockItem("char_doctor", "닥터 아카기", "시간 루프 프로젝트의 책임 연구원이자 설립자.", "과학자", "Character", "Icons/Doctor");
            AddMockItem("char_sub_pilot", "서브 파일럿", "루프 가속 장치 가동 시 보조 연산을 담당했던 조종사.", "승무원", "Character", "Icons/SubPilot");
            AddMockItem("char_unknown", "???", "인터페이스 외곽에서 노이즈 신호로만 검출되는 신원 불명의 존재.", "미식별", "Character", "Icons/Unknown");

            // 2. 아이템 카테고리 (해금 3, 미해금 3)
            AddMockItem("item_cato", "카토 알약", "감정을 강제적으로 억제하고 이상 생존력을 돕는 특수 알약.", "소모품", "Item", "Icons/Cato");
            AddMockItem("item_keycard", "보안 키카드", "중앙 연구소 및 격리 구역의 출입 권한이 기록된 전자식 카드.", "중요 아이템", "Item", "Icons/Keycard");
            AddMockItem("item_record_tape", "녹음된 테이프", "프로젝트 초기, 연구원들의 대화 음성이 기록되어 있는 마그네틱 테이프.", "단서", "Item", "Icons/RecordTape");
            AddMockItem("item_broken_watch", "정지된 회중시계", "루프가 시작된 첫 번째 시간 축에서 영구히 멈춰버린 기계식 시계.", "단서", "Item", "Icons/BrokenWatch");
            AddMockItem("item_blue_flower", "푸른 심연의 꽃", "연구실 지하층 고농도 차원 방사능 구역에서만 자라나는 신비로운 변이 꽃.", "식물", "Item", "Icons/BlueFlower");
            AddMockItem("item_documents", "연구소 일지", "프로젝트 이면에 감춰진 비윤리적 실험 실태가 기록된 내부 기밀 문서 번들.", "비밀 자료", "Item", "Icons/Documents");

            // 3. CG 갤러리 카테고리 (해금 3, 미해금 3)
            AddMockItem("cg_start_loop", "첫 번째 기억", "반복되는 시간 속에서 처음으로 눈을 떴을 때 마주한 흐릿한 천장.", "일러스트", "CG", "CG/StartLoop");
            AddMockItem("cg_collapsed", "종말의 풍경", "시간이 정지하고 차원이 붕괴되기 시작할 때의 기괴한 푸른 광원.", "일러스트", "CG", "CG/Collapsed");
            AddMockItem("cg_elena_smile", "마지막 미소", "모든 진실을 깨달은 엘레나가 주인공을 보며 지었던 알 수 없는 미소.", "일러스트", "CG", "CG/ElenaSmile");
            AddMockItem("cg_abyss", "심연의 도래", "중앙 가속기의 과부하로 차원의 틈새가 벌어져 실험실을 삼키는 광경.", "일러스트", "CG", "CG/Abyss");
            AddMockItem("cg_laboratory", "황폐한 실험실", "사람들의 흔적이 모두 끊긴 채 방사성 인광으로만 빛나는 폐쇄 연구 시설.", "일러스트", "CG", "CG/Laboratory");
            AddMockItem("cg_reunion", "기적적인 재회", "수십만 번의 루프 궤적 끝에 마침내 다시 만난 두 사람의 실루엣.", "일러스트", "CG", "CG/Reunion");

            // 4. 사운드룸 카테고리 (해금 3, 미해금 3)
            AddMockItem("bgm_theme", "A Loop Has No Love", "타이틀 화면의 쓸쓸함과 무한한 루프의 절망감을 담은 메인 테마곡.", "배경음악", "Sound", "Icons/SoundTheme");
            AddMockItem("bgm_plaza", "Frozen Air", "시간이 멈춰버린 정지된 광장에서 흘러나오는 서늘한 앰비언트 사운드.", "배경음악", "Sound", "Icons/SoundPlaza");
            AddMockItem("bgm_conflict", "Tense Loop", "주요 인물들과 대치하여 긴장감이 최고조에 이르렀을 때 연주되는 BGM.", "배경음악", "Sound", "Icons/SoundConflict");
            AddMockItem("bgm_hope", "Last Hope", "희미하게 어둠을 가르고 떠오르는 마지막 한 줄기 희망을 노래하는 스트링 곡.", "배경음악", "Sound", "Icons/SoundHope");
            AddMockItem("bgm_despair", "Cracked Timeline", "완벽했던 타임라인의 균열과 인물들의 내면적 붕괴를 소름끼치는 노이즈로 묘사한 음악.", "배경음악", "Sound", "Icons/SoundDespair");
            AddMockItem("bgm_silence", "Quiet World", "모든 상호작용이 끝나고 세상에 정적만이 감돌 때 재생되는 앰비언트 트랙.", "배경음악", "Sound", "Icons/SoundSilence");
        }

        private void AddMockItem(string id, string name, string desc, string tag, string category, string iconPath)
        {
            m_allItems.Add(new EncyclopediaItemDTO
            {
                Id = id,
                Name = name,
                Description = desc,
                Tag = tag,
                Category = category,
                IconPath = iconPath,
                IsUnlocked = m_unlockedItems.Contains(id)
            });
        }
        #endregion
    }
}
