using UnityEngine;
using UnityEngine.UI;
using System.Collections.Generic;
using Domain.InGame;
using TMPro;

namespace Features.InGame
{
    public class InGameInventoryView : MonoBehaviour
    {
        [SerializeField] private GameObject m_inventoryPanel;
        [SerializeField] private RectTransform m_itemGridParent;
        [SerializeField] private GameObject m_itemCardPrefab;

        [Header("카테고리 탭")]
        [SerializeField] private Button m_allTabButton;
        [SerializeField] private Button m_cluesTabButton;
        [SerializeField] private Button m_notesTabButton;
        [SerializeField] private Button m_keysTabButton;

        [Header("우측 상세 설명 패널")]
        [SerializeField] private TextMeshProUGUI m_detailNameText;
        [SerializeField] private TextMeshProUGUI m_detailDescriptionText;
        [SerializeField] private TextMeshProUGUI m_subplotProgressText;
        [SerializeField] private TextMeshProUGUI m_branchEffectText;

        private IInGameInventorySystem m_inventorySystem;
        private List<GameObject> m_spawnedCards = new List<GameObject>();
        private string m_currentSceneId = string.Empty;

        public void Initialize(IInGameInventorySystem inventorySystem, string currentSceneId)
        {
            m_inventorySystem = inventorySystem;
            m_currentSceneId = currentSceneId;

            if (m_allTabButton != null)
            {
                m_allTabButton.onClick.AddListener(() => func_OnTabSelected("All"));
            }
            if (m_cluesTabButton != null)
            {
                m_cluesTabButton.onClick.AddListener(() => func_OnTabSelected("Clue"));
            }
            if (m_notesTabButton != null)
            {
                m_notesTabButton.onClick.AddListener(() => func_OnTabSelected("Note"));
            }
            if (m_keysTabButton != null)
            {
                m_keysTabButton.onClick.AddListener(() => func_OnTabSelected("Key"));
            }

            func_Close();
        }

        public void func_Open()
        {
            if (m_inventoryPanel != null)
            {
                m_inventoryPanel.SetActive(true);
            }
            func_OnTabSelected("All");
        }

        public void func_Close()
        {
            if (m_inventoryPanel != null)
            {
                m_inventoryPanel.SetActive(false);
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

            if (m_inventorySystem == null || m_itemCardPrefab == null || m_itemGridParent == null)
            {
                return;
            }

            var items = m_inventorySystem.Items;
            for (int i = 0; i < items.Count; i++)
            {
                var item = items[i];
                if (category == "Clue" && !item.isClue)
                {
                    continue;
                }
                if (category == "Note" && item.isClue)
                {
                    continue;
                }

                var inst = Instantiate(m_itemCardPrefab, m_itemGridParent);
                if (inst != null)
                {
                    inst.SetActive(true);
                    m_spawnedCards.Add(inst);

                    var nameText = inst.transform.Find("NameText")?.GetComponent<TextMeshProUGUI>();
                    if (nameText != null)
                    {
                        nameText.text = item.name;
                    }

                    var glowOutline = inst.transform.Find("GlowOutline")?.gameObject;
                    if (glowOutline != null)
                    {
                        glowOutline.SetActive(item.connectedSubplotId == m_currentSceneId);
                    }

                    var btn = inst.GetComponent<Button>();
                    if (btn != null)
                    {
                        btn.onClick.AddListener(() => func_OnCardSelected(item));
                    }
                }
            }
        }

        private void func_OnCardSelected(InventoryItemDTO item)
        {
            if (item == null)
            {
                return;
            }

            if (m_detailNameText != null)
            {
                m_detailNameText.text = item.name;
            }
            if (m_detailDescriptionText != null)
            {
                m_detailDescriptionText.text = item.description;
            }
            if (m_subplotProgressText != null)
            {
                m_subplotProgressText.text = $"연결 서브플롯: {item.connectedSubplotId}";
            }
        }
    }
}
