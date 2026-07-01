using UnityEngine;
using UnityEngine.UI;
using System.Collections.Generic;
using Domain.InGame;
using TMPro;

namespace Features.InGame
{
    public class InGameEncyclopediaView : MonoBehaviour
    {
        [SerializeField] private GameObject m_encyclopediaPanel;
        [SerializeField] private RectTransform m_itemGridParent;
        [SerializeField] private GameObject m_encyclopediaCardPrefab;

        [Header("카테고리 탭")]
        [SerializeField] private Button m_characterTabButton;
        [SerializeField] private Button m_itemTabButton;
        [SerializeField] private Button m_cgTabButton;
        [SerializeField] private Button m_soundTabButton;

        [Header("우측 상세설명")]
        [SerializeField] private TextMeshProUGUI m_detailNameText;
        [SerializeField] private TextMeshProUGUI m_detailDescriptionText;

        private List<GameObject> m_spawnedCards = new List<GameObject>();
        private List<string> m_unlockedItems = new List<string>();

        public void Initialize(List<string> unlockedItems)
        {
            m_unlockedItems = unlockedItems != null ? unlockedItems : new List<string>();

            if (m_characterTabButton != null)
            {
                m_characterTabButton.onClick.AddListener(() => func_OnTabSelected("Character"));
            }
            if (m_itemTabButton != null)
            {
                m_itemTabButton.onClick.AddListener(() => func_OnTabSelected("Item"));
            }
            if (m_cgTabButton != null)
            {
                m_cgTabButton.onClick.AddListener(() => func_OnTabSelected("CG"));
            }
            if (m_soundTabButton != null)
            {
                m_soundTabButton.onClick.AddListener(() => func_OnTabSelected("Sound"));
            }

            func_Close();
        }

        public void func_Open()
        {
            if (m_encyclopediaPanel != null)
            {
                m_encyclopediaPanel.SetActive(true);
            }
            func_OnTabSelected("Character");
        }

        public void func_Close()
        {
            if (m_encyclopediaPanel != null)
            {
                m_encyclopediaPanel.SetActive(false);
            }
        }

        public void func_OnTabSelected(string category)
        {
            for (int i = 0; i < m_spawnedCards.Count; i++)
            {
                if (m_spawnedCards[i] != null)
                {
                    Destroy(m_spawnedCards[i]);
                }
            }
            m_spawnedCards.Clear();

            if (m_encyclopediaCardPrefab == null || m_itemGridParent == null)
            {
                return;
            }

            var mockItems = GetMockEncyclopediaData(category);
            for (int i = 0; i < mockItems.Count; i++)
            {
                var item = mockItems[i];
                var inst = Instantiate(m_encyclopediaCardPrefab, m_itemGridParent);
                if (inst != null)
                {
                    inst.SetActive(true);
                    m_spawnedCards.Add(inst);

                    var nameText = inst.transform.Find("NameText")?.GetComponent<TextMeshProUGUI>();
                    bool isUnlocked = m_unlockedItems.Contains(item.Id);

                    if (nameText != null)
                    {
                        nameText.text = isUnlocked ? item.Name : "???";
                    }

                    var img = inst.GetComponent<Image>();
                    if (img != null)
                    {
                        img.color = isUnlocked ? Color.white : new Color(0.3f, 0.3f, 0.3f, 0.8f);
                    }

                    var btn = inst.GetComponent<Button>();
                    if (btn != null)
                    {
                        btn.onClick.AddListener(() => func_OnCardSelected(item, isUnlocked));
                    }
                }
            }
        }

        private void func_OnCardSelected(MockEncyclopediaItem item, bool isUnlocked)
        {
            if (item == null)
            {
                return;
            }

            if (m_detailNameText != null)
            {
                m_detailNameText.text = isUnlocked ? item.Name : "???";
            }
            if (m_detailDescriptionText != null)
            {
                m_detailDescriptionText.text = isUnlocked ? item.Description : "아직 해금되지 않은 도감 항목입니다.";
            }
        }

        private List<MockEncyclopediaItem> GetMockEncyclopediaData(string category)
        {
            var list = new List<MockEncyclopediaItem>();
            if (category == "Character")
            {
                list.Add(new MockEncyclopediaItem { Id = "char_elena", Name = "엘레나", Description = "이 루프를 반복하는 주요 관찰 대상이자 동반자." });
                list.Add(new MockEncyclopediaItem { Id = "char_rain", Name = "레인", Description = "독자적으로 움직이는 수사관." });
            }
            else if (category == "Item")
            {
                list.Add(new MockEncyclopediaItem { Id = "item_cato", Name = "카토 알약", Description = "감정을 억제하고 생존을 돕는 파란 알약." });
            }
            return list;
        }

        public class MockEncyclopediaItem
        {
            public string Id;
            public string Name;
            public string Description;
        }
    }
}
